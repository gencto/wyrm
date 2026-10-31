//! History sync (ADR 0026): what every target shares. A target (InfluxDB,
//! PostgreSQL, …) implements [`Target`]: connect, write a batch, ping.
//! [`SyncApp`] runs it as a portable App (ADR 0023), the same code as a
//! WASM component or a process: it asks the history sink named in its
//! params for a batch (`next`), writes it with the target, and asks for the
//! next one with `after` = the batch's cursor, which confirms it (at least
//! once: the target replaces on `(key, t)`). It waits while there is
//! nothing new and backs off while the target is down.
//!
//! The link's params: `sink` (the sink's key, `wy/<site>/sys/history/sinks/<name>`), `batch`
//! (rows per batch, default 500, at most 5 000), `idle_s` (wait when nothing is new, default 5),
//! `retry_s` (longest wait after an error, default 60); every other key is the target's. The
//! target's secret (a password or a token) is never a param: ▸ Set Password keeps it in the
//! link's sealed store.

pub mod http;
#[cfg(any(test, feature = "testkit"))]
pub mod testkit;

use std::collections::BTreeMap;
use wyrm_core::meta::ParamMeta;
use wyrm_core::{ActionMeta, NodeMeta, Perm, Quality, Sample, Status, TypeCode, Value};
use wyrm_link_api::{App, AppError, Host, Level, ReqId, TimerId, Who};

pub type Map = BTreeMap<String, Value>;

/// One row of a batch.
#[derive(Debug, Clone, PartialEq)]
pub struct Row {
    /// Journal number in the broker's historian.
    pub seq: u64,
    /// The site of the point (from its key).
    pub site: String,
    /// The point's full key, `wy/<site>/…`: `(key, t)` is unique across sites.
    pub key: String,
    /// Sample time, UTC µs.
    pub t: u64,
    pub v: Value,
    pub q: Quality,
}

/// What a target takes at once.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Limits {
    /// Rows per write.
    pub rows: usize,
}

impl Default for Limits {
    fn default() -> Self {
        Self { rows: MAX_BATCH }
    }
}

/// How a target failed; the app acts on the class.
#[derive(Debug, Clone, PartialEq)]
pub enum TargetError {
    /// Network, throttling, a busy server: wait, send the same batch again.
    Retry(String),
    /// The connection is lost: connect again, then the same batch.
    Reconnect(String),
    /// Credentials, schema, a refused row: stop with the error until the
    /// params, the password or Resume change something.
    Fatal(String),
}

impl TargetError {
    pub fn message(&self) -> &str {
        match self {
            Self::Retry(m) | Self::Reconnect(m) | Self::Fatal(m) => m,
        }
    }
}

impl std::fmt::Display for TargetError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(self.message())
    }
}

/// A database the history goes to.
pub trait Target: Sized {
    /// The package and the link's root: `influxdb`, `postgres`, …
    const KIND: &'static str;
    const VERSION: &'static str;
    /// Check the target's params before anything connects; an unknown key
    /// is an error naming it.
    fn check(cfg: &Map) -> Result<(), String>;
    /// Open and authenticate (TCP or TLS through `net`), with the secret
    /// from ▸ Set Password.
    fn connect(net: &mut dyn Host, cfg: &Map, secret: Option<&str>) -> Result<Self, TargetError>;
    /// Create the table, index or bucket when the params allow; safe to repeat.
    fn prepare(&mut self, _net: &mut dyn Host) -> Result<(), TargetError> {
        Ok(())
    }
    /// Store one batch, replacing on `(key, t)`; `Ok` only when every row is stored.
    fn write(&mut self, net: &mut dyn Host, rows: &[Row]) -> Result<(), TargetError>;
    /// A cheap check of the connection.
    fn ping(&mut self, net: &mut dyn Host) -> Result<(), TargetError>;
    fn limits(&self) -> Limits {
        Limits::default()
    }
    fn close(self, _net: &mut dyn Host) {}
}

/// Rows per batch: by default and at most (the sink's bound).
pub const DEFAULT_BATCH: usize = 500;
pub const MAX_BATCH: usize = 5_000;
/// Waits (s): while nothing is new, and the longest after an error.
const DEFAULT_IDLE_S: u64 = 5;
const DEFAULT_RETRY_S: u64 = 60;
const FIRST_RETRY_MS: u64 = 1_000;
/// Store keys.
const SECRET: &str = "secret";
const PAUSED: &str = "paused";

/// The app's own params, out of the link's params.
#[derive(Debug, Clone, PartialEq)]
struct Own {
    sink: String,
    batch: usize,
    idle_ms: u64,
    retry_ms: u64,
}

fn bad(msg: impl Into<String>) -> AppError {
    AppError::new(Status::InvalidParameter, msg)
}

fn seconds(v: &Value, key: &str) -> Result<u64, AppError> {
    v.as_f64()
        .filter(|s| s.is_finite() && (1.0..=3600.0).contains(s))
        .map(|s| (s * 1000.0) as u64)
        .ok_or_else(|| bad(format!("params.{key}: 1 to 3600 seconds")))
}

/// Split the link's params into the app's and the target's.
fn split(config: Value) -> Result<(Own, Map), AppError> {
    let mut m = match config {
        Value::Map(m) => m,
        _ => return Err(bad("params: a map with sink")),
    };
    let sink = match m.remove("sink") {
        Some(Value::Str(s)) if sink_key(&s) => s,
        _ => {
            return Err(bad(
                "params.sink: the sink's key, wy/<site>/sys/history/sinks/<name>",
            ))
        }
    };
    let batch = match m.remove("batch") {
        None => DEFAULT_BATCH,
        Some(v) => v
            .as_f64()
            .filter(|b| b.is_finite() && (1.0..=MAX_BATCH as f64).contains(b))
            .map(|b| b as usize)
            .ok_or_else(|| bad(format!("params.batch: 1 to {MAX_BATCH}")))?,
    };
    let idle_ms = match m.remove("idle_s") {
        None => DEFAULT_IDLE_S * 1000,
        Some(v) => seconds(&v, "idle_s")?,
    };
    let retry_ms = match m.remove("retry_s") {
        None => DEFAULT_RETRY_S * 1000,
        Some(v) => seconds(&v, "retry_s")?,
    };
    Ok((
        Own {
            sink,
            batch,
            idle_ms,
            retry_ms,
        },
        m,
    ))
}

/// `wy/<site>/sys/history/sinks/<name>`, plain segments.
fn sink_key(s: &str) -> bool {
    let p: Vec<&str> = s.split('/').collect();
    p.len() == 6
        && p[0] == "wy"
        && p[2..5] == ["sys", "history", "sinks"]
        && [p[1], p[5]]
            .iter()
            .all(|x| !x.is_empty() && !x.contains(['*', '$', '~']) && *x != "..")
}

/// A batch as the sink answers it: `{rows: [{seq, key, t, v, q}], next}`.
fn parse_batch(v: Value) -> Result<(Vec<Row>, u64), String> {
    let Value::Map(mut m) = v else {
        return Err("batch: not a map".into());
    };
    let next = match m.remove("next") {
        Some(Value::UInt(n)) => n,
        _ => return Err("batch: no next".into()),
    };
    let rows = match m.remove("rows") {
        Some(Value::Array(a)) => a,
        _ => return Err("batch: no rows".into()),
    };
    let rows = rows
        .into_iter()
        .map(|r| {
            let Value::Map(mut r) = r else {
                return Err("row: not a map".to_owned());
            };
            let (Some(Value::UInt(seq)), Some(Value::Str(key)), Some(Value::UInt(t))) =
                (r.remove("seq"), r.remove("key"), r.remove("t"))
            else {
                return Err("row: seq, key, t".to_owned());
            };
            let q = match r.remove("q") {
                Some(Value::UInt(q)) => u8::try_from(q)
                    .ok()
                    .and_then(|q| Quality::try_from(q).ok())
                    .ok_or("row: q")?,
                _ => return Err("row: q".to_owned()),
            };
            let site = key.split('/').nth(1).unwrap_or_default().to_owned();
            Ok(Row {
                seq,
                site,
                key,
                t,
                v: r.remove("v").unwrap_or(Value::Null),
                q,
            })
        })
        .collect::<Result<Vec<_>, String>>()?;
    Ok((rows, next))
}

/// What the app is doing, shown in `status`.
#[derive(Debug, Clone, Copy, PartialEq)]
enum State {
    Connecting,
    Reading,
    Idle,
    Waiting,
    Failed,
    Paused,
}

impl State {
    fn name(self) -> &'static str {
        match self {
            State::Connecting => "connecting",
            State::Reading => "reading",
            State::Idle => "idle",
            State::Waiting => "waiting",
            State::Failed => "failed",
            State::Paused => "paused",
        }
    }
}

/// A [`Target`] as a portable App.
pub struct SyncApp<T: Target> {
    own: Own,
    cfg: Map,
    conn: Option<T>,
    /// The cursor of the last batch written: the next `next` confirms it.
    after: Option<u64>,
    pending: Option<ReqId>,
    timer: Option<TimerId>,
    retry_ms: u64,
    state: State,
    rows_sent: u64,
}

fn good(host: &dyn Host, v: Value) -> Sample {
    Sample {
        v,
        q: Quality::Good,
        t: host.now_us(),
    }
}

impl<T: Target> SyncApp<T> {
    fn show(&mut self, host: &mut dyn Host, state: State, error: Option<&str>) {
        self.state = state;
        let s = good(host, Value::from(state.name()));
        host.update("status", s);
        if let Some(e) = error {
            let s = good(host, Value::from(e));
            host.update("error", s);
        }
    }

    fn arm(&mut self, host: &mut dyn Host, ms: u64) {
        if let Some(t) = self.timer.take() {
            host.cancel_timer(t);
        }
        match host.set_timer(ms.max(1)) {
            Ok(t) => self.timer = Some(t),
            Err(e) => host.log(Level::Error, &format!("timer: {}", e.msg)),
        }
    }

    /// An error: wait longer each time, up to `retry_s`.
    fn back_off(&mut self, host: &mut dyn Host, why: &str) {
        self.show(host, State::Waiting, Some(why));
        let ms = self.retry_ms;
        self.retry_ms = (self.retry_ms * 2).min(self.own.retry_ms);
        self.arm(host, ms);
    }

    fn drop_conn(&mut self, host: &mut dyn Host) {
        if let Some(c) = self.conn.take() {
            c.close(host);
        }
    }

    fn secret(host: &dyn Host) -> Option<String> {
        host.store_get(SECRET)
            .and_then(|b| String::from_utf8(b).ok())
    }

    fn connect(&mut self, host: &mut dyn Host) -> Result<(), TargetError> {
        if self.conn.is_none() {
            self.show(host, State::Connecting, None);
            let secret = Self::secret(host);
            let mut c = T::connect(host, &self.cfg, secret.as_deref())?;
            c.prepare(host)?;
            self.conn = Some(c);
        }
        Ok(())
    }

    fn fail(&mut self, host: &mut dyn Host, e: TargetError) {
        match e {
            TargetError::Retry(m) => self.back_off(host, &m),
            TargetError::Reconnect(m) => {
                self.drop_conn(host);
                self.back_off(host, &m);
            }
            TargetError::Fatal(m) => {
                self.drop_conn(host);
                self.show(host, State::Failed, Some(&m));
                host.log(Level::Error, &format!("{}: {m}", T::KIND));
            }
        }
    }

    /// Connect if needed, then ask the sink for the next batch.
    fn tick(&mut self, host: &mut dyn Host) {
        if matches!(self.state, State::Paused | State::Failed) || self.pending.is_some() {
            return;
        }
        if let Err(e) = self.connect(host) {
            return self.fail(host, e);
        }
        let mut args = Map::new();
        let max = self
            .own
            .batch
            .min(self.conn.as_ref().map_or(MAX_BATCH, |c| c.limits().rows))
            .max(1);
        args.insert("max".into(), Value::UInt(max as u64));
        if let Some(a) = self.after {
            args.insert("after".into(), Value::UInt(a));
        }
        match host.invoke(&self.own.sink, "next", Value::Map(args)) {
            Ok(id) => {
                self.pending = Some(id);
                self.show(host, State::Reading, None);
            }
            Err(e) => self.back_off(host, &format!("next: {}", e.msg)),
        }
    }

    fn batch(&mut self, host: &mut dyn Host, reply: Value) {
        let (rows, next) = match parse_batch(reply) {
            Ok(b) => b,
            Err(e) => return self.back_off(host, &e),
        };
        if rows.is_empty() {
            self.after = Some(next);
            self.retry_ms = FIRST_RETRY_MS;
            self.show(host, State::Idle, None);
            return self.arm(host, self.own.idle_ms);
        }
        let Some(conn) = self.conn.as_mut() else {
            return self.arm(host, 1);
        };
        match conn.write(host, &rows) {
            Ok(()) => {
                self.after = Some(next);
                self.retry_ms = FIRST_RETRY_MS;
                self.rows_sent += rows.len() as u64;
                let s = good(host, Value::UInt(self.rows_sent));
                host.update("rows_sent", s);
                let s = good(host, Value::UInt(rows.len() as u64));
                host.update("last_batch", s);
                let s = good(host, Value::UInt(next));
                host.update("cursor", s);
                // the next batch at once: it also confirms this one
                self.arm(host, 1);
            }
            Err(e) => self.fail(host, e),
        }
    }

    /// Start again after a change (password, Resume): drop the connection
    /// and tick now.
    fn restart(&mut self, host: &mut dyn Host) {
        self.drop_conn(host);
        self.retry_ms = FIRST_RETRY_MS;
        self.show(host, State::Connecting, None);
        self.arm(host, 1);
    }
}

impl<T: Target> App for SyncApp<T> {
    const NAME: &'static str = T::KIND;
    const VERSION: &'static str = T::VERSION;

    fn start(host: &mut dyn Host, config: Value) -> Result<Self, AppError> {
        let (own, cfg) = split(config)?;
        T::check(&cfg).map_err(bad)?;
        for (path, about, ty) in [
            (
                "status",
                "connecting, reading, idle, waiting (after an error), failed (see error), paused",
                TypeCode::String,
            ),
            ("error", "The last error.", TypeCode::String),
            (
                "rows_sent",
                "Rows written since the link started.",
                TypeCode::Number,
            ),
            (
                "last_batch",
                "Rows of the last batch written, at its time.",
                TypeCode::Number,
            ),
            (
                "cursor",
                "The sink's journal entry after the last batch written.",
                TypeCode::Number,
            ),
        ] {
            host.declare_node(path, NodeMeta::leaf(ty).attr("description", about));
        }
        host.declare_action(
            "",
            "set_password",
            ActionMeta::new()
                .display("Set Password")
                .level(Perm::Config)
                .param(
                    "password",
                    ParamMeta::of(TypeCode::String)
                        .display("Password")
                        .editor("password")
                        .description(
                            "The database's password or token, kept in the link's sealed store; \
                             empty removes it.",
                        ),
                ),
        );
        host.declare_action(
            "",
            "test_connection",
            ActionMeta::new()
                .display("Test Connection")
                .level(Perm::Config)
                .result(wyrm_core::meta::ActionResult::Type(TypeCode::Map)),
        );
        host.declare_action(
            "",
            "pause",
            ActionMeta::new().display("Pause").level(Perm::Write),
        );
        host.declare_action(
            "",
            "resume",
            ActionMeta::new().display("Resume").level(Perm::Write),
        );
        let paused = host.store_get(PAUSED).is_some();
        let mut app = SyncApp {
            own,
            cfg,
            conn: None,
            after: None,
            pending: None,
            timer: None,
            retry_ms: FIRST_RETRY_MS,
            state: State::Connecting,
            rows_sent: 0,
        };
        let s = good(host, Value::UInt(0));
        host.update("rows_sent", s);
        if paused {
            app.show(host, State::Paused, None);
        } else {
            app.show(host, State::Connecting, None);
            app.arm(host, 1);
        }
        Ok(app)
    }

    fn on_set(
        &mut self,
        _host: &mut dyn Host,
        path: &str,
        _value: Value,
        _who: &Who,
    ) -> Result<(), AppError> {
        Err(AppError::new(Status::NotSupported, path))
    }

    fn on_invoke(
        &mut self,
        host: &mut dyn Host,
        path: &str,
        action: &str,
        args: Value,
        _who: &Who,
    ) -> Result<Value, AppError> {
        match (path, action) {
            ("", "set_password") => {
                let pw = match &args {
                    Value::Map(m) => match m.get("password") {
                        Some(Value::Str(s)) => s.clone(),
                        None | Some(Value::Null) => String::new(),
                        Some(_) => return Err(bad("password: text")),
                    },
                    _ => String::new(),
                };
                if pw.is_empty() {
                    host.store_delete(SECRET);
                } else {
                    host.store_put(SECRET, pw.as_bytes())?;
                }
                if self.state != State::Paused {
                    self.restart(host);
                }
                Ok(Value::Null)
            }
            ("", "test_connection") => {
                self.drop_conn(host);
                let r = self
                    .connect(host)
                    .and_then(|_| self.conn.as_mut().map_or(Ok(()), |c| c.ping(host)));
                let (ok, message) = match r {
                    Ok(()) => (true, "connected".to_owned()),
                    Err(e) => {
                        self.drop_conn(host);
                        (false, e.message().to_owned())
                    }
                };
                Ok(Value::Map(BTreeMap::from([
                    ("success".to_owned(), Value::Bool(ok)),
                    ("message".to_owned(), Value::Str(message)),
                ])))
            }
            ("", "pause") => {
                host.store_put(PAUSED, b"1")?;
                if let Some(t) = self.timer.take() {
                    host.cancel_timer(t);
                }
                self.drop_conn(host);
                self.show(host, State::Paused, None);
                Ok(Value::Null)
            }
            ("", "resume") => {
                host.store_delete(PAUSED);
                self.restart(host);
                Ok(Value::Null)
            }
            _ => Err(AppError::new(Status::NotSupported, action)),
        }
    }

    fn on_timer(&mut self, host: &mut dyn Host, timer: TimerId) {
        if self.timer == Some(timer) {
            self.timer = None;
            self.tick(host);
        }
    }

    fn on_reply(&mut self, host: &mut dyn Host, req: ReqId, result: Result<Value, AppError>) {
        if self.pending != Some(req) {
            return;
        }
        self.pending = None;
        match result {
            Ok(v) => self.batch(host, v),
            // e.g. before the broker trusts this link's key: try again later
            Err(e) => self.back_off(host, &format!("next: {}", e.msg)),
        }
    }

    fn stop(&mut self, host: &mut dyn Host) {
        self.drop_conn(host);
    }
}

#[cfg(test)]
mod tests;
