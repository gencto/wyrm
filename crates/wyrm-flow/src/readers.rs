//! The readers `load_value` (one read of a point) and `list_children` (the children of a node
//! as a list of rows) (ADR 0040 §4, spec 06 0.2.25).
//!
//! Both name what they read in a field that a port can change (`key` / `path`, inside
//! `key_scope` / `path_scope`: [`crate::scope`]). What makes them read:
//! - `auto_run` (default true): at the start, and when the field gets another key;
//! - `trigger`: an event, or a value that differs from the last one;
//! - `interval_ms`: every period.
//!
//! A read is no command: it may run at the start. The latest read wins; an answer of an
//! earlier one is dropped. Outputs: `out`, `ok` and `error` (events), `running`, `last_run`.

use crate::commands::{is_event, MAX_INTERVAL_MS, MIN_INTERVAL_MS};
use crate::def::Map;
use crate::nodes::{b, f, only, read_field, truthy, Io, Msg, Node, Out, PortType, Ports, Tasks};
use crate::scope;
use crate::sources::{DynKey, Switch};
use std::collections::BTreeMap;
use std::time::Duration;
use tokio::time::Instant;
use wyrm_core::{Quality, Sample, Status, Value};
use wyrm_link_sdk::now_us;

/// Rows of one `list_children` answer at most; a node with more gives an error.
pub const MAX_ROWS: usize = 1000;
/// A read that has no answer after this long is an error.
const READ_TIMEOUT: Duration = Duration::from_secs(5);

/// The read field of a reader type and its scope parameter.
fn field(ty: &str) -> (&'static str, &'static str) {
    if ty == "list_children" {
        ("path", "path_scope")
    } else {
        ("key", "key_scope")
    }
}

fn interval_ok(x: f64) -> bool {
    x == 0.0 || (MIN_INTERVAL_MS..=MAX_INTERVAL_MS).contains(&x)
}

/// Ports and config check of `load_value` and `list_children`.
pub(crate) fn ports(ty: &str, cfg: &Map) -> Result<Ports, String> {
    use PortType::*;
    let (key, key_scope) = field(ty);
    only(cfg, &[key, key_scope, "interval_ms", "auto_run", "enabled"])?;
    read_field(cfg, key, key_scope)?;
    b(cfg, "auto_run", true)?;
    b(cfg, "enabled", true)?;
    if !interval_ok(f(cfg, "interval_ms")?.unwrap_or(0.0)) {
        return Err(format!(
            "interval_ms: 0 (off) or {MIN_INTERVAL_MS}..={MAX_INTERVAL_MS}"
        ));
    }
    Ok(Ports {
        inputs: vec![
            ("trigger".into(), Any),
            (format!("in.{key}"), Any),
            ("in.interval_ms".into(), Number),
            ("in.auto_run".into(), Bool),
            ("in.enabled".into(), Bool),
        ],
        outputs: vec![
            ("out".into(), Any),
            ("ok".into(), Map),
            ("error".into(), Map),
            ("running".into(), Bool),
            ("last_run".into(), Number),
        ],
        echoes: Vec::new(),
    })
}

pub(crate) struct Reader {
    list: bool,
    field: &'static str,
    /// The key of the config, as written.
    start: Option<String>,
    key: DynKey,
    interval_ms: f64,
    auto_run: bool,
    enabled: bool,
    trigger: Option<Value>,
    /// The number of the read in flight: an answer with another number is dropped.
    seq: u64,
    running: bool,
    last: Option<Instant>,
    events: u64,
    params: BTreeMap<String, Value>,
    rev: u64,
    io: Option<Io>,
    tasks: Tasks,
}

pub(crate) fn build(ty: &str, cfg: &Map) -> Result<Box<dyn Node>, String> {
    ports(ty, cfg)?;
    let (key, key_scope) = field(ty);
    Ok(Box::new(Reader {
        list: ty == "list_children",
        field: key,
        start: match cfg.get(key) {
            Some(Value::Str(k)) => Some(k.clone()),
            _ => None,
        },
        key: DynKey::new(cfg, key_scope),
        interval_ms: f(cfg, "interval_ms")?.unwrap_or(0.0),
        auto_run: b(cfg, "auto_run", true)?,
        enabled: b(cfg, "enabled", true)?,
        trigger: None,
        seq: 0,
        running: false,
        last: None,
        events: 0,
        params: crate::catalog::effective_params(ty, cfg),
        rev: 0,
        io: None,
        tasks: Tasks::default(),
    }))
}

/// One read of a point: its stored sample.
async fn load(io: &Io, full: &str) -> Result<Msg, (Status, String)> {
    let replies = io
        .client
        .session()
        .get(format!("{full}/~val"))
        .timeout(READ_TIMEOUT)
        .await
        .map_err(|e| (Status::Disconnected, e.to_string()))?;
    let Ok(reply) = replies.recv_async().await else {
        return Err((Status::NotFound, "the point has no value".into()));
    };
    let sample = reply
        .result()
        .map_err(|_| (Status::NotFound, "the point has no value".to_owned()))?;
    let s: Sample = wyrm_core::codec::from_slice(&sample.payload().to_bytes())
        .map_err(|e| (Status::InvalidMessage, e.to_string()))?;
    Ok(Msg::new(s.v, s.q, s.t))
}

/// The children of a node, one row each: `{name, path}` and what its summary says.
async fn list(io: &Io, full: &str, written: &str) -> Result<Msg, (Status, String)> {
    let children = io.client.children(full).await.map_err(|e| {
        let status = match e.status {
            wyrm_core::status::StatusCode::Known(s) => s,
            _ => Status::InternalError,
        };
        (status, e.message)
    })?;
    if children.len() > MAX_ROWS {
        return Err((
            Status::ResourceExhausted,
            format!("more than {MAX_ROWS} children"),
        ));
    }
    let rows = children
        .into_iter()
        .map(|c| {
            let mut row = BTreeMap::from([
                (
                    "path".to_owned(),
                    Value::Str(format!("{}/{}", written.trim_end_matches('/'), c.name)),
                ),
                ("name".to_owned(), Value::Str(c.name)),
            ]);
            let m = c.meta;
            if let Some(t) = m.ty {
                row.insert("type".into(), Value::from(t.name()));
            }
            if let Some(d) = m.display {
                row.insert("display".into(), Value::Str(d));
            }
            if let Some(wyrm_core::meta::Profile::Name(is)) = m.is {
                row.insert("is".into(), Value::Str(is));
            }
            if let Some(wyrm_core::meta::TextOrCode::Text(u)) = m.unit {
                row.insert("unit".into(), Value::Str(u));
            }
            row.insert("writable".into(), Value::Bool(m.writable.is_some()));
            row.insert(
                "has_children".into(),
                Value::Bool(m.has_children.unwrap_or(false) || m.has_nodes.unwrap_or(false)),
            );
            Value::Map(row)
        })
        .collect();
    Ok(Msg::new(Value::Array(rows), Quality::Good, now_us()))
}

impl Reader {
    fn event(&mut self, port: &str, more: &[(&str, Value)], out: &mut Out) {
        self.events += 1;
        let mut m = BTreeMap::from([
            ("event".to_owned(), Value::Str(port.to_owned())),
            ("id".to_owned(), Value::UInt(self.events)),
        ]);
        m.extend(more.iter().map(|(k, v)| ((*k).to_owned(), v.clone())));
        out.emit(port, Msg::new(Value::Map(m), Quality::Good, now_us()));
    }

    fn failed(&mut self, code: Status, message: &str, out: &mut Out) {
        self.event(
            "error",
            &[
                ("code", Value::UInt(u64::from(code.code()))),
                ("message", Value::Str(message.to_owned())),
            ],
            out,
        );
    }

    fn set_running(&mut self, on: bool, out: &mut Out) {
        if self.running != on {
            self.running = on;
            out.emit(
                "running",
                Msg::new(Value::Bool(on), Quality::Good, now_us()),
            );
        }
    }

    fn set_param(&mut self, name: &str, v: Value) {
        self.params.insert(name.to_owned(), v);
        self.rev += 1;
    }

    /// Read the key in use now. The read before it, if it has no answer yet, is given up.
    fn read(&mut self, io: &Io, out: &mut Out) {
        if !self.enabled {
            return;
        }
        let Some(full) = self.key.current().map(str::to_owned) else {
            return;
        };
        let written = match self.params.get(self.field) {
            Some(Value::Str(w)) => w.clone(),
            _ => full.clone(),
        };
        self.seq += 1;
        self.last = Some(Instant::now());
        let (seq, list, io2) = (self.seq, self.list, io.clone());
        self.tasks = Tasks::default();
        self.tasks.0.push(tokio::spawn(async move {
            let work = async {
                if list {
                    self::list(&io2, &full, &written).await
                } else {
                    load(&io2, &full).await
                }
            };
            let r = match tokio::time::timeout(READ_TIMEOUT, work).await {
                Ok(r) => r,
                Err(_) => Err((Status::Timeout, "no answer".to_owned())),
            };
            let (v, q, t) = match r {
                Ok(m) => (
                    BTreeMap::from([
                        ("v".to_owned(), m.v),
                        ("q".to_owned(), Value::UInt(u64::from(m.q.code()))),
                    ]),
                    Quality::Good,
                    m.t,
                ),
                Err((code, message)) => (
                    BTreeMap::from([
                        ("code".to_owned(), Value::UInt(u64::from(code.code()))),
                        ("message".to_owned(), Value::Str(message)),
                    ]),
                    Quality::Bad,
                    now_us(),
                ),
            };
            (io2.inject)(&format!("__result.{seq}"), Msg::new(Value::Map(v), q, t));
        }));
        out.emit(
            "last_run",
            Msg::new(Value::UInt(now_us()), Quality::Good, now_us()),
        );
        self.set_running(true, out);
    }

    /// Another key from the port: the read in flight is given up, `out` is `null` and
    /// `uncertain` until the new key was read.
    fn switch(&mut self, sw: Switch, io: &Io, out: &mut Out) {
        self.tasks = Tasks::default();
        self.seq += 1;
        self.set_running(false, out);
        out.emit("out", Msg::new(Value::Null, Quality::Uncertain, now_us()));
        match sw {
            Switch::To { written, .. } => {
                self.set_param(self.field, Value::Str(written));
                if self.auto_run {
                    self.read(io, out);
                }
            }
            Switch::Off => self.set_param(self.field, Value::Null),
            Switch::Refused(why) => {
                self.set_param(self.field, Value::Null);
                self.failed(Status::InvalidParameter, &why, out);
            }
        }
    }
}

impl Node for Reader {
    fn start(&mut self, io: &Io) {
        self.io = Some(io.clone());
        if let Some(k) = &self.start {
            self.key.started(scope::full_key(&io.site, k));
            if self.auto_run {
                // the first read goes through the inbox, so its outputs are routed
                (io.inject)(
                    "__read",
                    Msg::new(Value::Null, Quality::Good, now_us()).at_start(),
                );
            }
        }
    }

    fn input(&mut self, port: &str, m: Msg, io: &Io, out: &mut Out) {
        if self.io.is_none() {
            self.io = Some(io.clone());
        }
        if let Some(seq) = port.strip_prefix("__result.") {
            if seq.parse::<u64>().ok() != Some(self.seq) {
                return; // an answer of a read that was given up
            }
            let Value::Map(r) = &m.v else { return };
            if m.q == Quality::Bad {
                let code = r.get("code").and_then(Value::as_f64).unwrap_or(0.0) as u8;
                let code = Status::try_from(code).unwrap_or(Status::InternalError);
                let message = match r.get("message") {
                    Some(Value::Str(s)) => s.clone(),
                    _ => String::new(),
                };
                self.failed(code, &message, out);
            } else {
                let q = r
                    .get("q")
                    .and_then(Value::as_f64)
                    .and_then(|q| Quality::try_from(q as u8).ok())
                    .unwrap_or(Quality::Bad);
                let v = r.get("v").cloned().unwrap_or(Value::Null);
                out.emit("out", Msg::new(v, q, m.t));
                self.event("ok", &[], out);
            }
            self.set_running(false, out);
            return;
        }
        match port {
            "__read" => self.read(io, out),
            "trigger" => {
                let prev = self.trigger.replace(m.v.clone());
                let fire = !m.start
                    && m.v != Value::Null
                    && (is_event(&m.v) || prev.as_ref() != Some(&m.v));
                if fire {
                    self.read(io, out);
                }
            }
            "in.interval_ms" => {
                if let Some(x) = m.v.as_f64().filter(|x| x.is_finite() && interval_ok(*x)) {
                    self.interval_ms = x;
                    self.set_param("interval_ms", Value::Float(x));
                }
            }
            "in.auto_run" => {
                self.auto_run = truthy(&m.v);
                self.set_param("auto_run", Value::Bool(self.auto_run));
            }
            "in.enabled" => {
                self.enabled = truthy(&m.v);
                self.set_param("enabled", Value::Bool(self.enabled));
            }
            p if p.strip_prefix("in.") == Some(self.field) => {
                if let Some(sw) = self.key.offer(m.v, &io.site) {
                    self.switch(sw, io, out);
                }
            }
            _ => {}
        }
    }

    fn tick_every(&self) -> Option<Duration> {
        if self.key.waiting() {
            return Some(scope::RESUBSCRIBE);
        }
        (self.enabled && self.interval_ms >= MIN_INTERVAL_MS)
            .then(|| Duration::from_secs_f64(self.interval_ms / 1000.0))
    }

    fn first_tick_now(&self) -> bool {
        false
    }

    fn tick(&mut self, _now: u64, out: &mut Out) {
        let Some(io) = self.io.clone() else { return };
        if let Some(sw) = self.key.due(&io.site) {
            self.switch(sw, &io, out);
            return;
        }
        if self.key.waiting() || self.running || self.interval_ms < MIN_INTERVAL_MS {
            return;
        }
        // the clock may be the key's 100 ms: a period is counted from the last read
        let period = Duration::from_secs_f64(self.interval_ms / 1000.0);
        if self
            .last
            .is_none_or(|t| t.elapsed() + Duration::from_millis(5) >= period)
        {
            self.read(&io, out);
        }
    }

    fn live_params(&self) -> Option<(u64, &BTreeMap<String, Value>)> {
        Some((self.rev, &self.params))
    }
}
