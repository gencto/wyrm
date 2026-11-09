//! The command blocks `invoke` (the action block) and `set` (ADR 0040 §2, spec 06 0.2.23).
//!
//! What runs a command:
//! - a sample on `in`, as before (`invoke`: every sample that passes `on`; `set`: a value that
//!   passes `on`/`deadband`, while `auto_run` is true);
//! - `trigger`: an event, or a value that differs from the last one on that port;
//! - `auto_run` of `invoke`: a sample on `arg.<name>` that changes the argument;
//! - `interval_ms`: every period, the first time one full period after the node started;
//! - the engine's action `dataflows/<id>/~act/trigger {node}` (internal port `__trigger`).
//!
//! A deploy, a hot swap or a restart never runs a command through `trigger`, `auto_run` or
//! `interval_ms`: a sample that was born at the start ([`Msg::start`]) only gives the field
//! its value. `enabled: false` runs nothing.
//!
//! One block, its behaviour set by its fields (owner decision 2026-11-09): there is no block
//! type per behaviour. `run_on_start: true` is the one sanctioned exception to the rule above,
//! chosen per block: the block runs exactly once, [`START_SETTLE`] after the flow started (a
//! deploy, a hot swap, a reload, a restart), so the start values of its arguments and of `in`
//! are in. The default is false.
//!
//! Outputs: `sent` (an event when the request leaves), `ok` (an event on success), `error`
//! (an event with `code` and `message`), `running`, `last_run`; `invoke` also `result` and the
//! older `out`. In a preview ([`Mode::Preview`]) the node holds no client: it reports what it
//! would send to the probe, fires `sent` and `last_run`, and never `ok`, `error` or `result`.

use crate::def::Map;
use crate::nodes::{
    b, command_target, f, one_of, only, req_s, truthy, Io, Mode, Msg, Node, Out, PortType, Ports,
    SinkOp,
};
use crate::watch::Probe;
use std::collections::BTreeMap;
use std::sync::Arc;
use std::time::Duration;
use tracing::debug;
use wyrm_core::{Quality, Status, Value};
use wyrm_link_sdk::now_us;

/// The shortest `interval_ms` above 0.
pub const MIN_INTERVAL_MS: f64 = 100.0;
/// The longest `interval_ms`: one day.
pub const MAX_INTERVAL_MS: f64 = 86_400_000.0;
/// With `run_on_start`: how long after its start a block makes its one run, so the start
/// values of bound fields have arrived.
pub const START_SETTLE: Duration = Duration::from_millis(250);
/// Arguments of one `invoke` at most.
pub const MAX_ARGS: usize = 64;
/// Calls an `invoke` node holds while its caller is busy; more are refused with `busy`.
const COMMAND_QUEUE: usize = 256;

fn interval_ok(x: f64) -> bool {
    x == 0.0 || (MIN_INTERVAL_MS..=MAX_INTERVAL_MS).contains(&x)
}

/// The argument names of an `invoke`: the keys of `args`.
fn arg_names(cfg: &Map) -> Result<Vec<String>, String> {
    match cfg.get("args") {
        None => Ok(Vec::new()),
        Some(Value::Map(m)) => {
            if m.len() > MAX_ARGS {
                return Err(format!("args: at most {MAX_ARGS}"));
            }
            for k in m.keys() {
                if k.is_empty() || k.len() > 128 || k.starts_with("__") {
                    return Err(format!("args.{k}: a name of 1..=128 bytes, not __…"));
                }
            }
            Ok(m.keys().cloned().collect())
        }
        Some(_) => Err("args: expected a map {<argument>: <value>}".into()),
    }
}

/// Ports and config check of `invoke` and `set`.
pub(crate) fn ports(ty: &str, cfg: &Map) -> Result<Ports, String> {
    use PortType::*;
    req_s(cfg, "path")?;
    b(cfg, "allow_bad", false)?;
    b(cfg, "auto_run", ty == "set")?;
    b(cfg, "enabled", true)?;
    b(cfg, "run_on_start", false)?;
    if !interval_ok(f(cfg, "interval_ms")?.unwrap_or(0.0)) {
        return Err(format!(
            "interval_ms: 0 (off) or {MIN_INTERVAL_MS}..={MAX_INTERVAL_MS}"
        ));
    }
    let mut inputs: Vec<(String, PortType)> = vec![
        ("in".into(), Any),
        ("trigger".into(), Any),
        ("in.interval_ms".into(), Number),
        ("in.auto_run".into(), Bool),
        ("in.enabled".into(), Bool),
    ];
    let events = [("sent", Map), ("ok", Map), ("error", Map)];
    let state = [("running", Bool), ("last_run", Number)];
    let mut outputs: Vec<(String, PortType)> = Vec::new();
    if ty == "invoke" {
        only(
            cfg,
            &[
                "path",
                "action",
                "args",
                "on",
                "allow_bad",
                "interval_ms",
                "auto_run",
                "enabled",
                "run_on_start",
            ],
        )?;
        req_s(cfg, "action")?;
        one_of(cfg, "on", &["any", "rising", "falling", "change"], "any")?;
        inputs.extend(
            arg_names(cfg)?
                .into_iter()
                .map(|n| (format!("arg.{n}"), Any)),
        );
        outputs.extend([("out".to_owned(), Any), ("result".to_owned(), Any)]);
    } else {
        only(
            cfg,
            &[
                "path",
                "on",
                "deadband",
                "allow_bad",
                "interval_ms",
                "auto_run",
                "enabled",
                "run_on_start",
            ],
        )?;
        one_of(cfg, "on", &["any", "change"], "change")?;
        f(cfg, "deadband")?;
    }
    outputs.extend(
        events
            .iter()
            .chain(&state)
            .map(|(n, t)| ((*n).to_owned(), *t)),
    );
    Ok(Ports {
        inputs,
        outputs,
        echoes: Vec::new(),
    })
}

/// Edge detection of `invoke.on`.
fn should_fire(on: &str, last: &mut Option<Value>, v: &Value) -> bool {
    let prev = last.replace(v.clone());
    match on {
        "rising" => truthy(v) && !prev.as_ref().is_some_and(truthy),
        "falling" => !truthy(v) && prev.as_ref().is_some_and(truthy),
        "change" => prev.as_ref() != Some(v),
        _ => true,
    }
}

/// An event value (ADR 0032 §4): `{event, id}`.
pub(crate) fn is_event(v: &Value) -> bool {
    matches!(v, Value::Map(m) if matches!(m.get("event"), Some(Value::Str(_))) && m.contains_key("id"))
}

enum What {
    Invoke {
        action: String,
        /// Each argument's value: its constant, then the last sample on `arg.<name>`.
        args: Map,
        on: String,
        last_in: Option<Value>,
        /// The last sample on `in`: what `"$in"` in `args` stands for.
        input: Value,
    },
    Set {
        change: bool,
        deadband: f64,
        /// The last value written (what `on: change` compares with).
        written: Option<Value>,
        /// The last value on `in`: what a trigger or the interval writes.
        value: Option<Value>,
    },
}

/// What one run sends.
enum Job {
    Invoke(Map),
    Set(Value),
}

type Call = (u64, bool, Map);
type Write = Option<(u64, bool, Value)>;

enum Sink {
    /// A deployed flow: one writer task per node, in order.
    Live {
        calls: Option<tokio::sync::mpsc::Sender<Call>>,
        writes: Option<tokio::sync::watch::Sender<Write>>,
    },
    /// A preview: no client and no writer; the probe gets what the node would send.
    Capture {
        probe: Arc<Probe>,
        node: String,
        key: String,
    },
}

pub(crate) struct Command {
    what: What,
    path: String,
    interval_ms: f64,
    auto_run: bool,
    enabled: bool,
    allow_bad: bool,
    /// The last sample on `trigger`.
    trigger: Option<Value>,
    /// The number of the last run sent to the writer.
    seq: u64,
    running: bool,
    events: u64,
    params: BTreeMap<String, Value>,
    rev: u64,
    sink: Sink,
    /// For the interval's runs: a tick has no `Io` of its own.
    io: Option<Io>,
    /// `run_on_start`: the one run at the start is still to make.
    start_run: bool,
}

/// An `invoke` or `set` node (config checked by [`ports`]), for a deployed flow or a preview.
pub(crate) fn build(ty: &str, id: &str, cfg: &Map, mode: &Mode) -> Result<Box<dyn Node>, String> {
    ports(ty, cfg)?;
    let what = if ty == "invoke" {
        What::Invoke {
            action: req_s(cfg, "action")?.to_owned(),
            args: match cfg.get("args") {
                Some(Value::Map(m)) => m.clone(),
                _ => Map::new(),
            },
            on: one_of(cfg, "on", &["any", "rising", "falling", "change"], "any")?.to_owned(),
            last_in: None,
            input: Value::Null,
        }
    } else {
        What::Set {
            change: one_of(cfg, "on", &["any", "change"], "change")? == "change",
            deadband: f(cfg, "deadband")?.unwrap_or(0.0),
            written: None,
            value: None,
        }
    };
    let sink = match mode {
        Mode::Live => Sink::Live {
            calls: None,
            writes: None,
        },
        Mode::Preview(sb) => Sink::Capture {
            probe: sb.probe.clone(),
            node: id.to_owned(),
            key: sb.full_key(&command_target(ty, cfg).ok_or("path: required")?),
        },
    };
    Ok(Box::new(Command {
        what,
        path: req_s(cfg, "path")?.to_owned(),
        interval_ms: f(cfg, "interval_ms")?.unwrap_or(0.0),
        auto_run: b(cfg, "auto_run", ty == "set")?,
        enabled: b(cfg, "enabled", true)?,
        allow_bad: b(cfg, "allow_bad", false)?,
        trigger: None,
        seq: 0,
        running: false,
        events: 0,
        params: crate::catalog::effective_params(ty, cfg),
        rev: 0,
        sink,
        io: None,
        start_run: b(cfg, "run_on_start", false)?,
    }))
}

impl Command {
    /// An event on `port`: always sent, as `{event, id}` plus `more`.
    fn event(&mut self, port: &str, more: &[(&str, Value)], start: bool, out: &mut Out) {
        self.events += 1;
        let mut m = BTreeMap::from([
            ("event".to_owned(), Value::Str(port.to_owned())),
            ("id".to_owned(), Value::UInt(self.events)),
        ]);
        m.extend(more.iter().map(|(k, v)| ((*k).to_owned(), v.clone())));
        let mut msg = Msg::new(Value::Map(m), Quality::Good, now_us());
        msg.start = start;
        out.emit(port, msg);
    }

    fn set_param(&mut self, name: &str, v: Value) {
        self.params.insert(name.to_owned(), v);
        self.rev += 1;
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

    /// What a run sends now; `None` when there is nothing to send (a `set` without a value).
    fn job(&mut self) -> Option<Job> {
        match &mut self.what {
            What::Invoke { args, input, .. } => Some(Job::Invoke(
                // `"$in"` stands for the last value on `in`
                args.iter()
                    .map(|(k, v)| {
                        let v = match v {
                            Value::Str(s) if s == "$in" => input.clone(),
                            v => v.clone(),
                        };
                        (k.clone(), v)
                    })
                    .collect(),
            )),
            What::Set { value, written, .. } => {
                let v = value.clone()?;
                *written = Some(v.clone());
                Some(Job::Set(v))
            }
        }
    }

    /// Run the command once. `start`: the cause was born at the start (only a sample on `in`
    /// can be: the older behaviour); the answers carry the mark on.
    fn run(&mut self, start: bool, io: &Io, out: &mut Out) {
        if !self.enabled {
            return;
        }
        let Some(job) = self.job() else { return };
        let seq = self.seq + 1;
        match &mut self.sink {
            Sink::Capture { probe, node, key } => {
                let (op, value) = match job {
                    Job::Invoke(args) => (SinkOp::Invoke, Value::Map(args)),
                    Job::Set(v) => (SinkOp::Set, v),
                };
                probe.sink(node, op, key, value);
                self.seq = seq;
                self.event("sent", &[], start, out);
                out.emit(
                    "last_run",
                    Msg::new(Value::UInt(now_us()), Quality::Good, now_us()),
                );
            }
            Sink::Live { calls, writes } => match job {
                Job::Invoke(args) => {
                    let What::Invoke { action, .. } = &self.what else {
                        return;
                    };
                    // one caller task, in order: a task per call could run a later call first
                    let tx = calls.get_or_insert_with(|| {
                        let (tx, mut rx) = tokio::sync::mpsc::channel::<Call>(COMMAND_QUEUE);
                        let (io2, node, action) =
                            (io.clone(), io.full_key(&self.path), action.clone());
                        tokio::spawn(async move {
                            while let Some((seq, start, args)) = rx.recv().await {
                                (io2.inject)("__sent", internal(seq, start, None));
                                let r = io2
                                    .client
                                    .invoke_one(&node, &action, Value::Map(args))
                                    .await
                                    .map(|v| v.unwrap_or(Value::Null));
                                (io2.inject)("__result", internal(seq, start, Some(r)));
                            }
                        });
                        tx
                    });
                    if tx.try_send((seq, start, args)).is_ok() {
                        self.seq = seq;
                        self.set_running(true, out);
                    } else {
                        debug!(path = %self.path, "invoke: calls queued to the limit, call refused");
                        self.failed(Status::Busy.code(), "calls queued to the limit", out);
                    }
                }
                Job::Set(v) => {
                    // one writer task writes the newest value, in order (a task per sample
                    // could write an older value last)
                    let tx = writes.get_or_insert_with(|| {
                        let (tx, mut rx) = tokio::sync::watch::channel::<Write>(None);
                        let (io2, node) = (io.clone(), io.full_key(&self.path));
                        tokio::spawn(async move {
                            while rx.changed().await.is_ok() {
                                let Some((seq, start, v)) = rx.borrow_and_update().clone() else {
                                    continue;
                                };
                                (io2.inject)("__sent", internal(seq, start, None));
                                let r = io2.client.set(&node, v).await.map(|()| Value::Null);
                                if let Err(e) = &r {
                                    debug!("flow set {node}: {e}");
                                }
                                (io2.inject)("__result", internal(seq, start, Some(r)));
                            }
                        });
                        tx
                    });
                    tx.send_replace(Some((seq, start, v)));
                    self.seq = seq;
                    self.set_running(true, out);
                }
            },
        }
    }

    /// The `error` event, and for `invoke` the older `out` (the message, quality `bad`).
    fn failed(&mut self, code: u8, message: &str, out: &mut Out) {
        self.event(
            "error",
            &[
                ("code", Value::UInt(u64::from(code))),
                ("message", Value::Str(message.to_owned())),
            ],
            false,
            out,
        );
        if matches!(self.what, What::Invoke { .. }) {
            out.emit(
                "out",
                Msg::new(Value::Str(message.to_owned()), Quality::Bad, now_us()),
            );
        }
    }

    /// A sample on `trigger`: an event runs the command, and so does a value that differs
    /// from the last one there. `null` and (without `allow_bad`) a bad sample run nothing; a
    /// sample born at the start only gives the port its value.
    fn triggered(&mut self, m: &Msg) -> bool {
        let prev = self.trigger.replace(m.v.clone());
        if m.start || m.v == Value::Null || (m.q == Quality::Bad && !self.allow_bad) {
            return false;
        }
        is_event(&m.v) || prev.as_ref() != Some(&m.v)
    }
}

/// A message of the writer task to its node: `__sent` (`r` none) or `__result`.
fn internal(seq: u64, start: bool, r: Option<Result<Value, wyrm_client::ClientError>>) -> Msg {
    let mut m = BTreeMap::from([("seq".to_owned(), Value::UInt(seq))]);
    let q = match r {
        None => Quality::Good,
        Some(Ok(v)) => {
            m.insert("v".into(), v);
            Quality::Good
        }
        Some(Err(e)) => {
            m.insert("code".into(), Value::UInt(u64::from(e.status.code())));
            m.insert("message".into(), Value::Str(e.to_string()));
            Quality::Bad
        }
    };
    let mut msg = Msg::new(Value::Map(m), q, now_us());
    msg.start = start;
    msg
}

impl Node for Command {
    fn start(&mut self, io: &Io) {
        self.io = Some(io.clone());
    }

    fn input(&mut self, port: &str, m: Msg, io: &Io, out: &mut Out) {
        if self.io.is_none() {
            self.io = Some(io.clone());
        }
        match port {
            "__sent" => {
                self.event("sent", &[], m.start, out);
                out.emit("last_run", Msg::new(Value::UInt(m.t), Quality::Good, m.t));
            }
            "__result" => {
                let Value::Map(r) = &m.v else { return };
                if m.q == Quality::Bad {
                    let code = r.get("code").and_then(Value::as_f64).unwrap_or(0.0) as u8;
                    let message = match r.get("message") {
                        Some(Value::Str(s)) => s.clone(),
                        _ => String::new(),
                    };
                    self.failed(code, &message, out);
                } else {
                    if matches!(self.what, What::Invoke { .. }) {
                        let v = r.get("v").cloned().unwrap_or(Value::Null);
                        out.emit("result", Msg::new(v.clone(), Quality::Good, m.t));
                        out.emit("out", Msg::new(v, Quality::Good, m.t));
                    }
                    self.event("ok", &[], m.start, out);
                }
                // the writer is idle once the last run it was given has answered
                if r.get("seq").and_then(Value::as_f64) == Some(self.seq as f64) {
                    self.set_running(false, out);
                }
            }
            // the engine's `trigger` action: a person or a tool asked for a run
            "__trigger" => self.run(false, io, out),
            "trigger" => {
                if self.triggered(&m) {
                    self.run(false, io, out);
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
            "in" => {
                let bad = m.q == Quality::Bad && !self.allow_bad;
                let fire = match &mut self.what {
                    What::Invoke {
                        on, last_in, input, ..
                    } => {
                        // never act on bad data
                        !bad && {
                            *input = m.v.clone();
                            should_fire(on, last_in, &m.v)
                        }
                    }
                    What::Set {
                        change,
                        deadband,
                        written,
                        value,
                    } => {
                        !bad && {
                            *value = Some(m.v.clone());
                            let within = *change
                                && match (written.as_ref().and_then(Value::as_f64), m.v.as_f64()) {
                                    (Some(a), Some(b)) => (a - b).abs() <= *deadband,
                                    _ => written.as_ref() == Some(&m.v),
                                };
                            self.auto_run && !within
                        }
                    }
                };
                if fire {
                    self.run(m.start, io, out);
                }
            }
            p => {
                let Some(name) = p.strip_prefix("arg.") else {
                    return;
                };
                let auto = self.auto_run;
                let What::Invoke { args, .. } = &mut self.what else {
                    return;
                };
                let Some(slot) = args.get_mut(name) else {
                    return;
                };
                let changed = *slot != m.v;
                *slot = m.v.clone();
                let live = Value::Map(args.clone());
                self.set_param("args", live);
                // a value born at the start gives the argument its value and runs nothing
                let bad = m.q == Quality::Bad && !self.allow_bad;
                if auto && changed && !m.start && !bad {
                    self.run(false, io, out);
                }
            }
        }
    }

    fn tick_every(&self) -> Option<Duration> {
        if self.start_run {
            return Some(START_SETTLE);
        }
        (self.enabled && self.interval_ms >= MIN_INTERVAL_MS)
            .then(|| Duration::from_secs_f64(self.interval_ms / 1000.0))
    }

    /// The interval's first run is one full period after the start, never at it.
    fn first_tick_now(&self) -> bool {
        false
    }

    fn tick(&mut self, _now: u64, out: &mut Out) {
        // `run_on_start`: exactly one run, born at the start (its answers carry the mark, so
        // they run no other command through a trigger). A disabled block makes none.
        if std::mem::take(&mut self.start_run) {
            // a `set` that already wrote its start value (`auto_run`) does not write it twice
            let wrote = matches!(
                &self.what,
                What::Set {
                    written: Some(_),
                    ..
                }
            );
            if let Some(io) = self.io.clone().filter(|_| !wrote) {
                self.run(true, &io, out);
            }
            return;
        }
        // a period is skipped while the run before it has not answered
        if self.running {
            return;
        }
        if let Some(io) = self.io.clone() {
            self.run(false, &io, out);
        }
    }

    fn live_params(&self) -> Option<(u64, &BTreeMap<String, Value>)> {
        Some((self.rev, &self.params))
    }

    fn seeds(&self) -> Vec<(String, Value)> {
        match &self.what {
            What::Invoke { args, .. } => args
                .iter()
                .filter(|(_, v)| **v != Value::Null)
                .map(|(k, v)| (format!("arg.{k}"), v.clone()))
                .collect(),
            What::Set { .. } => Vec::new(),
        }
    }
}
