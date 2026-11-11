//! The readers `load_value` (one read of a point) and `list_children` (the children of a node
//! as a list of rows) (ADR 0040 §4, spec 06 0.2.25), `load_history` (the historian's rows of a
//! point as a table) and `get_node` (a node's summary and its actions) (ADR 0044 §4).
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
/// A read that has no answer after this long is an error; a history read, after the longer.
const READ_TIMEOUT: Duration = Duration::from_secs(5);
const HISTORY_TIMEOUT: Duration = Duration::from_secs(30);
/// Rows of one `load_history` at most (its `limit`).
pub const MAX_HISTORY_ROWS: usize = 10_000;
/// `load_history.rollup`'s choices (spec 01 `agg`).
pub const ROLLUPS: &[&str] = &[
    "none", "avg", "min", "max", "sum", "count", "first", "last", "delta", "and", "or",
];

/// What a reader reads.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum What {
    Value,
    Children,
    History,
    Node,
}

fn what(ty: &str) -> What {
    match ty {
        "list_children" => What::Children,
        "load_history" => What::History,
        "get_node" => What::Node,
        _ => What::Value,
    }
}

/// The read field of a reader type and its scope parameter.
fn field(ty: &str) -> (&'static str, &'static str) {
    if ty == "list_children" {
        ("path", "path_scope")
    } else {
        ("key", "key_scope")
    }
}

/// `load_history`'s parameters beyond the reader's own, each with the port `in.<p>`.
const HISTORY_PARAMS: &[&str] = &["time_range", "rollup", "window", "limit", "time_zone"];

/// A `window` of spec 01: `<n>` and one of `s m h d w`, or empty (none).
fn window_ok(w: &str) -> bool {
    w.is_empty()
        || (w.len() <= 12
            && w.ends_with(['s', 'm', 'h', 'd', 'w'])
            && w[..w.len() - 1].parse::<u32>().is_ok_and(|n| n > 0))
}

fn limit_ok(x: f64) -> bool {
    (1.0..=MAX_HISTORY_ROWS as f64).contains(&x)
}

/// The history query of `load_history`'s parameters at `now`: `None` with the reason when a
/// parameter is no good.
fn history_query(
    p: &BTreeMap<String, Value>,
    now: i64,
) -> Result<wyrm_client::HistoryQuery, String> {
    let text = |k: &str| match p.get(k) {
        Some(Value::Str(s)) => s.trim().to_owned(),
        _ => String::new(),
    };
    let tz = crate::blocks::date::zone(p.get("time_zone").unwrap_or(&Value::Null))
        .ok_or("time_zone: no such zone")?;
    let range = text("time_range");
    let r =
        crate::blocks::date::range(if range.is_empty() { "today" } else { &range }, now, &tz, 0)
            .ok_or_else(|| format!("time_range: {range} is no range"))?;
    let at = |us: i64| {
        jiff::Timestamp::from_microsecond(us)
            .map(|t| t.to_string())
            .map_err(|e| e.to_string())
    };
    let rollup = text("rollup");
    let window = text("window");
    if !window_ok(&window) {
        return Err(format!("window: {window} is not <n>s, m, h, d or w"));
    }
    let limit = p
        .get("limit")
        .and_then(Value::as_f64)
        .filter(|x| limit_ok(*x))
        .map_or(MAX_HISTORY_ROWS, |x| x as usize);
    Ok(wyrm_client::HistoryQuery {
        from: at(r.start)?,
        to: at(r.end)?,
        agg: (!rollup.is_empty() && rollup != "none").then_some(rollup),
        window: (!window.is_empty()).then_some(window),
        limit: Some(limit),
    })
}

fn interval_ok(x: f64) -> bool {
    x == 0.0 || (MIN_INTERVAL_MS..=MAX_INTERVAL_MS).contains(&x)
}

/// Ports and config check of `load_value` and `list_children`.
pub(crate) fn ports(ty: &str, cfg: &Map) -> Result<Ports, String> {
    use PortType::*;
    let (key, key_scope) = field(ty);
    let mut known = vec![key, key_scope, "interval_ms", "auto_run", "enabled"];
    if what(ty) == What::History {
        known.extend(HISTORY_PARAMS);
    }
    only(cfg, &known)?;
    read_field(cfg, key, key_scope)?;
    if what(ty) == What::History {
        for k in ["time_range", "rollup", "window", "time_zone"] {
            crate::nodes::s(cfg, k)?;
        }
        if let Some(Value::Str(r)) = cfg.get("rollup") {
            if !ROLLUPS.contains(&r.as_str()) {
                return Err(format!("rollup: one of {ROLLUPS:?}"));
            }
        }
        if !f(cfg, "limit")?.is_none_or(limit_ok) {
            return Err(format!("limit: 1..={MAX_HISTORY_ROWS}"));
        }
        let p = crate::catalog::effective_params(ty, cfg);
        history_query(&p, now_us() as i64)?;
    }
    b(cfg, "auto_run", true)?;
    b(cfg, "enabled", true)?;
    if !interval_ok(f(cfg, "interval_ms")?.unwrap_or(0.0)) {
        return Err(format!(
            "interval_ms: 0 (off) or {MIN_INTERVAL_MS}..={MAX_INTERVAL_MS}"
        ));
    }
    let mut inputs: Vec<(String, PortType)> = vec![
        ("trigger".into(), Any),
        (format!("in.{key}"), Any),
        ("in.interval_ms".into(), Number),
        ("in.auto_run".into(), Bool),
        ("in.enabled".into(), Bool),
    ];
    let mut outputs: Vec<(String, PortType)> = vec![("out".into(), Any)];
    match what(ty) {
        What::History => {
            inputs.extend(HISTORY_PARAMS.iter().map(|p| {
                let t = if *p == "limit" { Number } else { Any };
                (format!("in.{p}"), t)
            }));
        }
        What::Node => outputs.push(("actions".into(), Any)),
        _ => {}
    }
    outputs.extend([
        ("ok".into(), Map),
        ("error".into(), Map),
        ("running".into(), Bool),
        ("last_run".into(), Number),
    ]);
    Ok(Ports {
        inputs,
        outputs,
        echoes: Vec::new(),
    })
}

pub(crate) struct Reader {
    what: What,
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
    /// A query field changed while a read was in flight: read again when it ends (a change
    /// never gives up a read that runs, so a slow history read still answers).
    again: bool,
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
        what: what(ty),
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
        again: false,
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

/// The history of a point as a table `{t, v, q}` (`q` null for a rollup row), and whether the
/// answer reached the limit (there may be more).
async fn history(
    io: &Io,
    full: &str,
    q: wyrm_client::HistoryQuery,
) -> Result<Msg, (Status, String)> {
    let limit = q.limit.unwrap_or(MAX_HISTORY_ROWS);
    let rows = io.client.history(full, &q).await.map_err(|e| {
        let status = match e.status {
            wyrm_core::status::StatusCode::Known(s) => s,
            _ => Status::InternalError,
        };
        (status, e.message)
    })?;
    let truncated = rows.len() >= limit;
    let mut t = crate::blocks::table::Table::new(vec!["t".into(), "v".into(), "q".into()]);
    for r in rows.into_iter().take(limit) {
        t.rows.push(BTreeMap::from([
            ("t".to_owned(), Value::UInt(r.t)),
            ("v".to_owned(), r.v),
            (
                "q".to_owned(),
                r.q.map_or(Value::Null, |q| Value::UInt(q.code().into())),
            ),
        ]));
    }
    let n = t.rows.len();
    let v = t.to_value().ok_or((
        Status::ResourceExhausted,
        format!("{n} rows are more than a table holds (512 KiB)"),
    ))?;
    let mut m = Msg::new(
        Value::Map(BTreeMap::from([
            ("table".to_owned(), v),
            ("rows".to_owned(), Value::UInt(n as u64)),
            ("truncated".to_owned(), Value::Bool(truncated)),
        ])),
        Quality::Good,
        now_us(),
    );
    m.key = None;
    Ok(m)
}

/// A node's summary and its actions: `{summary, actions}`; `actions` is a table of
/// `{name, display, group, level, params}`, `params` a list of `{name, type, default, required,
/// display, description, unit, enum}`.
async fn node(io: &Io, full: &str) -> Result<Msg, (Status, String)> {
    let m = io.client.meta(full).await.map_err(|e| {
        let status = match e.status {
            wyrm_core::status::StatusCode::Known(s) => s,
            _ => Status::InternalError,
        };
        (status, e.message)
    })?;
    let name = full.rsplit('/').next().unwrap_or(full).to_owned();
    let text = |s: Option<String>| s.map_or(Value::Null, Value::Str);
    let unit = |u: Option<wyrm_core::meta::TextOrCode>| match u {
        Some(wyrm_core::meta::TextOrCode::Text(t)) => Value::Str(t),
        _ => Value::Null,
    };
    let enums = |e: Option<Vec<String>>| {
        e.map_or(Value::Null, |e| {
            Value::Array(e.into_iter().map(Value::Str).collect())
        })
    };
    let summary = BTreeMap::from([
        ("name".to_owned(), Value::Str(name)),
        ("display".to_owned(), text(m.display)),
        (
            "type".to_owned(),
            m.ty.map_or(Value::Null, |t| Value::from(t.name())),
        ),
        ("unit".to_owned(), unit(m.unit)),
        ("enum".to_owned(), enums(m.enum_values)),
        ("writable".to_owned(), Value::Bool(m.writable.is_some())),
        (
            "is".to_owned(),
            match m.is {
                Some(wyrm_core::meta::Profile::Name(n)) => Value::Str(n),
                _ => Value::Null,
            },
        ),
        (
            "has_children".to_owned(),
            Value::Bool(m.has_children.unwrap_or(false) || m.has_nodes.unwrap_or(false)),
        ),
    ]);
    let mut actions = crate::blocks::table::Table::new(
        ["name", "display", "group", "level", "params"]
            .map(String::from)
            .to_vec(),
    );
    for (a, am) in m.actions.unwrap_or_default().into_iter().take(MAX_ROWS) {
        let params = am
            .params
            .into_iter()
            .map(|(pn, pm)| {
                Value::Map(BTreeMap::from([
                    ("name".to_owned(), Value::Str(pn)),
                    (
                        "type".to_owned(),
                        pm.ty.map_or(Value::Null, |t| Value::from(t.name())),
                    ),
                    ("default".to_owned(), pm.default.unwrap_or(Value::Null)),
                    (
                        "required".to_owned(),
                        Value::Bool(pm.required.unwrap_or(false)),
                    ),
                    ("display".to_owned(), text(pm.display)),
                    ("description".to_owned(), text(pm.description)),
                    ("unit".to_owned(), unit(pm.unit)),
                    ("enum".to_owned(), enums(pm.enum_values)),
                ]))
            })
            .collect();
        actions.rows.push(BTreeMap::from([
            ("name".to_owned(), Value::Str(a)),
            ("display".to_owned(), text(am.display)),
            ("group".to_owned(), text(am.group)),
            (
                "level".to_owned(),
                am.level.map_or(Value::Null, |l| Value::from(l.name())),
            ),
            ("params".to_owned(), Value::Array(params)),
        ]));
    }
    let actions = actions.to_value().ok_or((
        Status::ResourceExhausted,
        "the actions are more than a table holds".to_owned(),
    ))?;
    Ok(Msg::new(
        Value::Map(BTreeMap::from([
            ("summary".to_owned(), Value::Map(summary)),
            ("actions".to_owned(), actions),
        ])),
        Quality::Good,
        now_us(),
    ))
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
        let query = if self.what == What::History {
            match history_query(&self.params, now_us() as i64) {
                Ok(q) => Some(q),
                Err(why) => {
                    self.failed(Status::InvalidParameter, &why, out);
                    return;
                }
            }
        } else {
            None
        };
        self.seq += 1;
        self.last = Some(Instant::now());
        let (seq, what, io2) = (self.seq, self.what, io.clone());
        self.tasks = Tasks::default();
        self.tasks.0.push(tokio::spawn(async move {
            let work = async {
                match (what, query) {
                    (What::Children, _) => self::list(&io2, &full, &written).await,
                    (What::History, Some(q)) => history(&io2, &full, q).await,
                    (What::Node, _) => node(&io2, &full).await,
                    _ => load(&io2, &full).await,
                }
            };
            let timeout = if what == What::History {
                HISTORY_TIMEOUT
            } else {
                READ_TIMEOUT
            };
            let r = match tokio::time::timeout(timeout, work).await {
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
                match (self.what, v) {
                    (What::History, Value::Map(h)) => {
                        let table = h.get("table").cloned().unwrap_or(Value::Null);
                        out.emit("out", Msg::new(table, q, m.t));
                        // a full answer may hold more: the event says so, the table is not cut
                        let more = [
                            ("rows", h.get("rows").cloned().unwrap_or(Value::Null)),
                            (
                                "truncated",
                                h.get("truncated").cloned().unwrap_or(Value::Null),
                            ),
                        ];
                        self.event("ok", &more, out);
                    }
                    (What::Node, Value::Map(n)) => {
                        let summary = n.get("summary").cloned().unwrap_or(Value::Null);
                        let actions = n.get("actions").cloned().unwrap_or(Value::Null);
                        out.emit("out", Msg::new(summary, q, m.t));
                        out.emit("actions", Msg::new(actions, q, m.t));
                        self.event("ok", &[], out);
                    }
                    (_, v) => {
                        out.emit("out", Msg::new(v, q, m.t));
                        self.event("ok", &[], out);
                    }
                }
            }
            self.set_running(false, out);
            if std::mem::take(&mut self.again) {
                self.read(io, out);
            }
            return;
        }
        match port {
            "__read" => self.read(io, out),
            // `dataflows/<id>/~act/trigger {node}` (ADR 0044 §4): one read now
            "__trigger" => self.read(io, out),
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
            p if self.what == What::History
                && p.strip_prefix("in.")
                    .is_some_and(|n| HISTORY_PARAMS.contains(&n)) =>
            {
                let name = &p[3..];
                let ok = match (name, &m.v) {
                    ("limit", v) => v.as_f64().is_some_and(limit_ok),
                    ("rollup", Value::Str(r)) => ROLLUPS.contains(&r.as_str()),
                    (_, Value::Str(_) | Value::Null) => true,
                    _ => false,
                };
                if ok && self.params.get(name) != Some(&m.v) {
                    self.set_param(name, m.v);
                    // a read is no command: a field born at the start reads too
                    if self.auto_run {
                        if self.running {
                            self.again = true;
                        } else {
                            self.read(io, out);
                        }
                    }
                }
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

#[cfg(test)]
mod tests {
    use super::*;

    fn params(kv: &[(&str, Value)]) -> BTreeMap<String, Value> {
        let cfg: BTreeMap<String, Value> = kv
            .iter()
            .map(|(k, v)| ((*k).to_owned(), v.clone()))
            .chain([("key".to_owned(), Value::from("downstream/l/t"))])
            .collect();
        crate::catalog::effective_params("load_history", &cfg)
    }

    /// 2026-10-29T13:00:00Z
    const T: i64 = 1_793_278_800_000_000;

    #[test]
    fn history_queries() {
        let q = history_query(&params(&[]), T).unwrap();
        assert_eq!(
            (q.from.as_str(), q.to.as_str()),
            ("2026-10-29T00:00:00Z", "2026-10-29T23:59:59.999999Z")
        );
        assert_eq!(
            (q.agg, q.window, q.limit),
            (None, None, Some(MAX_HISTORY_ROWS))
        );
        let q = history_query(
            &params(&[
                ("time_range", "yesterday".into()),
                ("time_zone", "Europe/Kyiv".into()),
                ("rollup", "max".into()),
                ("window", "1h".into()),
                ("limit", Value::UInt(24)),
            ]),
            T,
        )
        .unwrap();
        assert_eq!(q.from, "2026-10-27T22:00:00Z");
        assert_eq!(
            q.params(),
            "history=2026-10-27T22:00:00Z..2026-10-28T21:59:59.999999Z&agg=max&window=1h&limit=24"
        );
        // a range from date_range's this_range, in the zone
        let q = history_query(
            &params(&[(
                "time_range",
                "2026-10-01T00:00:00/2026-10-31T23:59:59".into(),
            )]),
            T,
        )
        .unwrap();
        assert_eq!(q.to, "2026-10-31T23:59:59.999999Z");
        for bad in [
            ("time_range", Value::from("soon")),
            ("window", Value::from("5x")),
            ("window", Value::from("0m")),
            ("time_zone", Value::from("Nowhere/City")),
        ] {
            assert!(
                history_query(&params(std::slice::from_ref(&bad)), T).is_err(),
                "{bad:?}"
            );
        }
        // the config check gives the reason at compile time
        let cfg = |kv: &[(&str, Value)]| -> Map {
            kv.iter()
                .map(|(k, v)| ((*k).to_owned(), v.clone()))
                .chain([("key".to_owned(), Value::from("downstream/l/t"))])
                .collect()
        };
        assert!(ports("load_history", &cfg(&[("window", "5x".into())])).is_err());
        assert!(ports("load_history", &cfg(&[("rollup", "median".into())])).is_err());
        assert!(ports("load_history", &cfg(&[("limit", Value::UInt(10_001))])).is_err());
        let p = ports("load_history", &cfg(&[])).unwrap();
        assert!(p.inputs.iter().any(|(n, _)| n == "in.time_range"));
        let p = ports("get_node", &cfg(&[])).unwrap();
        assert_eq!(p.outputs[1].0, "actions");
    }
}
