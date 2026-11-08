//! Live values of a deployed flow (ADR 0038 §3–§4): `dataflows/<id>/~act/watch` (a stream) and
//! `dataflows/<id>/~act/ports` (one snapshot).
//!
//! Each flow has one [`Probe`]. Its node tasks record the last sample of every port and the
//! effective parameters into it, but only while a watch (or a `ports` call) holds it open: with
//! none open, a node task checks one atomic and does nothing more. So a port that had no sample
//! since recording began is absent from a row. The values stay [`KEEP`] after the last watch
//! closes, so an editor that opens its watch again at once keeps them.
//!
//! Rows (CBOR maps, text keys; `[v, q]` with `q` the quality code):
//! 1. `{t, snapshot: true, nodes: {<node>: {in: {<port>: [v, q]}, out: {…}, params: {<p>: v}}}}`;
//! 2. `{t, snapshot: false, nodes: {…}}` with only what changed (empty `in`/`out`/`params` left
//!    out), at most `max_hz` rows per second, the latest value winning inside a period;
//! 3. `{t, nodes: {}}` after [`HEARTBEAT`] without a row;
//! 4. the stream ends after [`TTL`], on a redeploy (last row `{t, redeployed: <version>}`), on
//!    remove, or when the engine stops.

use crate::def::FlowDef;
use crate::nodes::{Msg, SinkOp};
use std::collections::{BTreeMap, BTreeSet};
use std::future::Future;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;
use tokio::sync::watch;
use tokio::time::Instant;
use wyrm_core::{Quality, Status, Value};
use wyrm_link_sdk::{now_us, LinkError};

/// Watches of one flow at most.
pub const MAX_PER_FLOW: usize = 8;
/// Watches of one site (every flow of the engine) at most.
pub const MAX_PER_SITE: usize = 64;
/// Rows per second when the caller gives no `max_hz`.
pub const DEFAULT_HZ: f64 = 4.0;
/// The highest `max_hz`.
pub const MAX_HZ: f64 = 20.0;
/// A row without changes after this long without a row.
pub const HEARTBEAT: Duration = Duration::from_secs(10);
/// A watch ends after this long; the editor opens it again.
pub const TTL: Duration = Duration::from_secs(30 * 60);
/// The action's `timeout_ms`: the gateway's idle wait per reply is this plus 5 s.
pub const TIMEOUT_MS: u32 = 30_000;
/// How long recorded values stay after the last watch closed.
pub const KEEP: Duration = Duration::from_secs(5);
/// How long an opening watch waits for the node tasks to give their parameters.
const ASK_WAIT: Duration = Duration::from_millis(200);

/// Why the watches of a flow end.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum End {
    /// A new version replaced the flow: the last row says which.
    Redeployed(u64),
    /// The flow was removed, or the engine stops.
    Gone,
}

#[derive(Debug, Clone)]
struct PortRec {
    v: Value,
    q: Quality,
    seq: u64,
}

#[derive(Debug, Clone)]
struct ParamRec {
    v: Value,
    seq: u64,
}

#[derive(Debug, Default)]
struct NodeRec {
    seq: u64,
    ins: BTreeMap<String, PortRec>,
    outs: BTreeMap<String, PortRec>,
    params: BTreeMap<String, ParamRec>,
}

/// What a preview's sink would have done last (ADR 0038 §5).
#[derive(Debug, Clone)]
struct SinkRec {
    op: SinkOp,
    key: String,
    v: Value,
    seq: u64,
}

#[derive(Debug, Default)]
struct Data {
    seq: u64,
    nodes: BTreeMap<String, NodeRec>,
    /// A preview's sinks: the latest per node.
    sinks: BTreeMap<String, SinkRec>,
    /// When the last watch closed.
    idle_since: Option<Instant>,
    /// The node tasks that run, and the last request for parameters each answered.
    alive: BTreeMap<String, u64>,
}

impl Data {
    fn node(&mut self, id: &str) -> &mut NodeRec {
        self.nodes.entry(id.to_owned()).or_default()
    }
}

/// The recorder of one flow's live values, shared by its node tasks and its watches.
pub struct Probe {
    open: AtomicUsize,
    data: Mutex<Data>,
    /// The record's `seq`, for the watches to wake on.
    wake: watch::Sender<u64>,
    /// A request to the node tasks: record your parameters now.
    ask: watch::Sender<u64>,
    end: watch::Sender<Option<End>>,
    /// Each node's parameters from its config (`crate::catalog::effective_params`).
    statics: BTreeMap<String, BTreeMap<String, Value>>,
}

impl Probe {
    pub fn new(def: &FlowDef) -> Arc<Self> {
        let statics = def
            .nodes
            .iter()
            .map(|(id, n)| (id.clone(), crate::catalog::effective_params(&n.ty, &n.cfg)))
            .collect();
        Arc::new(Self {
            open: AtomicUsize::new(0),
            data: Mutex::new(Data::default()),
            wake: watch::channel(0).0,
            ask: watch::channel(0).0,
            end: watch::channel(None).0,
            statics,
        })
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, Data> {
        self.data.lock().unwrap_or_else(|p| p.into_inner())
    }

    /// Whether node tasks record: a watch holds the probe open.
    pub fn on(&self) -> bool {
        self.open.load(Ordering::Relaxed) > 0
    }

    /// Open watches (and `ports` calls in flight).
    pub fn watchers(&self) -> usize {
        self.open.load(Ordering::Relaxed)
    }

    /// The parameters of `node` from its config.
    pub fn statics(&self, node: &str) -> BTreeMap<String, Value> {
        self.statics.get(node).cloned().unwrap_or_default()
    }

    /// End every watch of this flow.
    pub fn end(&self, why: End) {
        self.end.send_replace(Some(why));
    }

    /// Requests for parameters, for one node task.
    pub(crate) fn asks(&self) -> watch::Receiver<u64> {
        self.ask.subscribe()
    }

    /// A node task starts (`true`) or ends.
    pub(crate) fn alive(&self, node: &str, yes: bool) {
        let mut d = self.lock();
        if yes {
            d.alive.insert(node.to_owned(), 0);
        } else {
            d.alive.remove(node);
        }
    }

    /// A node task answers request `gen` with its live parameters (`None`: its config).
    pub(crate) fn answer(&self, node: &str, gen: u64, params: Option<&BTreeMap<String, Value>>) {
        let changed = {
            let mut d = self.lock();
            if let Some(g) = d.alive.get_mut(node) {
                *g = gen;
            }
            match params {
                Some(p) => record_params(&mut d, node, p),
                None => false,
            }
        };
        if changed {
            self.bump();
        }
    }

    /// One call of a node: the sample it took (`(port, v, q)`), what it sent, and its live
    /// parameters when they changed.
    pub(crate) fn record(
        &self,
        node: &str,
        input: Option<(String, Value, Quality)>,
        outs: &[(String, Msg)],
        params: Option<&BTreeMap<String, Value>>,
    ) {
        let changed = {
            let mut d = self.lock();
            let mut changed = false;
            if let Some((port, v, q)) = input {
                changed |= record_port(&mut d, node, true, &port, v, q);
            }
            for (port, m) in outs {
                changed |= record_port(&mut d, node, false, port, m.v.clone(), m.q);
            }
            if let Some(p) = params {
                changed |= record_params(&mut d, node, p);
            }
            changed
        };
        if changed {
            self.bump();
        }
    }

    /// A preview's sink `node` would do `op` on `key` with `v` (the latest per node is kept).
    pub(crate) fn sink(&self, node: &str, op: SinkOp, key: &str, v: Value) {
        {
            let mut d = self.lock();
            d.seq += 1;
            let seq = d.seq;
            d.sinks.insert(
                node.to_owned(),
                SinkRec {
                    op,
                    key: key.to_owned(),
                    v,
                    seq,
                },
            );
        }
        self.bump();
    }

    fn bump(&self) {
        let seq = self.lock().seq;
        self.wake.send_replace(seq);
    }

    /// Wait (at most `max`) until `nodes` node tasks run and the flow is quiet: a round of
    /// asks in which no node recorded anything. Each task answers an ask once its inbox is
    /// empty, so what the nodes sent at start (a variable's value, a parameter's echo) is in
    /// the next snapshot. A busy flow (a source at 20 Hz) is never quiet: `max` bounds it.
    pub async fn settle(&self, nodes: usize, max: Duration) {
        let deadline = Instant::now() + max;
        while self.lock().alive.len() < nodes && Instant::now() < deadline {
            tokio::time::sleep(Duration::from_millis(2)).await;
        }
        while Instant::now() < deadline {
            let before = self.lock().seq;
            self.ask_params().await;
            if self.lock().seq == before {
                return;
            }
        }
    }

    /// Hold the probe open: node tasks record until the guard drops.
    pub fn hold(self: &Arc<Self>) -> Hold {
        let first = self.open.fetch_add(1, Ordering::Relaxed) == 0;
        if first {
            let mut d = self.lock();
            // values older than the last watch may be stale: start again
            if d.idle_since.is_some_and(|t| t.elapsed() > KEEP) {
                for n in d.nodes.values_mut() {
                    n.ins.clear();
                    n.outs.clear();
                }
            }
            d.idle_since = None;
        }
        Hold(self.clone())
    }

    /// Ask every running node task for its parameters and wait (at most [`ASK_WAIT`]) for the
    /// answers.
    async fn ask_params(&self) {
        let mut gen = 0;
        self.ask.send_modify(|g| {
            *g += 1;
            gen = *g;
        });
        let deadline = Instant::now() + ASK_WAIT;
        loop {
            if self.lock().alive.values().all(|g| *g >= gen) || Instant::now() >= deadline {
                return;
            }
            tokio::time::sleep(Duration::from_millis(5)).await;
        }
    }

    /// Row 1: every recorded port and every parameter of the nodes in `only` (all: `None`),
    /// and the record's `seq`.
    fn snapshot(&self, only: Option<&BTreeSet<String>>) -> (Value, u64) {
        let d = self.lock();
        let mut nodes = BTreeMap::new();
        for (id, statics) in &self.statics {
            if only.is_some_and(|o| !o.contains(id)) {
                continue;
            }
            let rec = d.nodes.get(id);
            let ports = |pick: fn(&NodeRec) -> &BTreeMap<String, PortRec>| {
                Value::Map(
                    rec.map(|r| {
                        pick(r)
                            .iter()
                            .map(|(p, x)| (p.clone(), sample(&x.v, x.q)))
                            .collect()
                    })
                    .unwrap_or_default(),
                )
            };
            let mut params = statics.clone();
            if let Some(r) = rec {
                for (p, x) in &r.params {
                    params.insert(p.clone(), x.v.clone());
                }
            }
            nodes.insert(
                id.clone(),
                Value::Map(BTreeMap::from([
                    ("in".to_owned(), ports(|r| &r.ins)),
                    ("out".to_owned(), ports(|r| &r.outs)),
                    ("params".to_owned(), Value::Map(params)),
                ])),
            );
        }
        let mut r = row(Some(true), nodes);
        add_sinks(&mut r, &d, 0, only);
        (r, d.seq)
    }

    /// Row 2: what changed after `since`, or `None` when nothing did (in `only`); and the
    /// record's `seq`.
    fn changes(&self, since: u64, only: Option<&BTreeSet<String>>) -> (Option<Value>, u64) {
        let d = self.lock();
        let mut nodes = BTreeMap::new();
        for (id, r) in &d.nodes {
            if r.seq <= since || only.is_some_and(|o| !o.contains(id)) {
                continue;
            }
            let ports = |m: &BTreeMap<String, PortRec>| -> BTreeMap<String, Value> {
                m.iter()
                    .filter(|(_, x)| x.seq > since)
                    .map(|(p, x)| (p.clone(), sample(&x.v, x.q)))
                    .collect()
            };
            let mut n = BTreeMap::new();
            for (k, m) in [("in", ports(&r.ins)), ("out", ports(&r.outs))] {
                if !m.is_empty() {
                    n.insert(k.to_owned(), Value::Map(m));
                }
            }
            let params: BTreeMap<String, Value> = r
                .params
                .iter()
                .filter(|(_, x)| x.seq > since)
                .map(|(p, x)| (p.clone(), x.v.clone()))
                .collect();
            if !params.is_empty() {
                n.insert("params".into(), Value::Map(params));
            }
            nodes.insert(id.clone(), Value::Map(n));
        }
        let mut r = row(Some(false), nodes);
        // a row of changes: nodes that changed, or sinks that acted
        let out = (add_sinks(&mut r, &d, since, only) || has_nodes(&r)).then_some(r);
        (out, d.seq)
    }
}

fn has_nodes(row: &Value) -> bool {
    matches!(row, Value::Map(m) if matches!(m.get("nodes"), Some(Value::Map(n)) if !n.is_empty()))
}

/// Adds `sinks: [{node, op, key, value}]` to `row`: each sink of a node in `only` (all: `None`)
/// that acted after `since`, the latest per node. `false` when there is none (no key added).
fn add_sinks(row: &mut Value, d: &Data, since: u64, only: Option<&BTreeSet<String>>) -> bool {
    let list: Vec<Value> = d
        .sinks
        .iter()
        .filter(|(n, s)| s.seq > since && only.is_none_or(|o| o.contains(*n)))
        .map(|(n, s)| {
            Value::Map(BTreeMap::from([
                ("node".to_owned(), Value::from(n.as_str())),
                ("op".to_owned(), Value::from(s.op.name())),
                ("key".to_owned(), Value::from(s.key.as_str())),
                ("value".to_owned(), s.v.clone()),
            ]))
        })
        .collect();
    if list.is_empty() {
        return false;
    }
    if let Value::Map(m) = row {
        m.insert("sinks".into(), Value::Array(list));
    }
    true
}

/// Keeps a [`Probe`] recording; the last one to drop starts the [`KEEP`] time.
pub struct Hold(Arc<Probe>);

impl Drop for Hold {
    fn drop(&mut self) {
        if self.0.open.fetch_sub(1, Ordering::Relaxed) == 1 {
            self.0.lock().idle_since = Some(Instant::now());
        }
    }
}

fn record_port(d: &mut Data, node: &str, input: bool, port: &str, v: Value, q: Quality) -> bool {
    let seq = d.seq + 1;
    let n = d.node(node);
    let m = if input { &mut n.ins } else { &mut n.outs };
    if m.get(port).is_some_and(|x| x.v == v && x.q == q) {
        return false;
    }
    m.insert(port.to_owned(), PortRec { v, q, seq });
    n.seq = seq;
    d.seq = seq;
    true
}

fn record_params(d: &mut Data, node: &str, params: &BTreeMap<String, Value>) -> bool {
    let seq = d.seq + 1;
    let n = d.node(node);
    let mut changed = false;
    for (p, v) in params {
        if n.params.get(p).is_some_and(|x| &x.v == v) {
            continue;
        }
        n.params.insert(p.clone(), ParamRec { v: v.clone(), seq });
        changed = true;
    }
    if changed {
        n.seq = seq;
        d.seq = seq;
    }
    changed
}

/// `[v, q]`.
fn sample(v: &Value, q: Quality) -> Value {
    Value::Array(vec![v.clone(), Value::UInt(u64::from(q.code()))])
}

fn row(snapshot: Option<bool>, nodes: BTreeMap<String, Value>) -> Value {
    let mut m = BTreeMap::from([
        ("t".to_owned(), Value::UInt(now_us())),
        ("nodes".to_owned(), Value::Map(nodes)),
    ]);
    if let Some(s) = snapshot {
        m.insert("snapshot".into(), Value::Bool(s));
    }
    Value::Map(m)
}

fn last_row(why: End) -> Option<Value> {
    match why {
        End::Redeployed(v) => Some(Value::Map(BTreeMap::from([
            ("t".to_owned(), Value::UInt(now_us())),
            ("redeployed".to_owned(), Value::UInt(v)),
        ]))),
        End::Gone => None,
    }
}

/// `max_hz` from the action's arguments: more than 0, at most [`MAX_HZ`]; [`DEFAULT_HZ`] when
/// absent.
pub fn period(args: &Value) -> Result<Duration, LinkError> {
    let hz = match args {
        Value::Map(m) => match m.get("max_hz") {
            None | Some(Value::Null) => DEFAULT_HZ,
            Some(v) => v
                .as_f64()
                .ok_or_else(|| LinkError::invalid_parameter("max_hz: a number"))?,
        },
        _ => DEFAULT_HZ,
    };
    if !(hz > 0.0 && hz <= MAX_HZ) {
        return Err(LinkError::invalid_parameter(format!(
            "max_hz: more than 0, at most {MAX_HZ}"
        )));
    }
    Ok(Duration::from_secs_f64(1.0 / hz))
}

/// `nodes` from the action's arguments: node ids of `def`; absent or empty: every node.
pub fn only(args: &Value, def: &FlowDef) -> Result<Option<BTreeSet<String>>, LinkError> {
    let list = match args {
        Value::Map(m) => match m.get("nodes") {
            None | Some(Value::Null) => return Ok(None),
            Some(Value::Array(a)) => a,
            Some(_) => return Err(LinkError::invalid_parameter("nodes: a list of node ids")),
        },
        _ => return Ok(None),
    };
    let mut out = BTreeSet::new();
    for v in list {
        let Value::Str(id) = v else {
            return Err(LinkError::invalid_parameter("nodes: a list of node ids"));
        };
        if !def.nodes.contains_key(id) {
            return Err(LinkError::invalid_parameter(format!(
                "nodes: {id} is not a node of {}",
                def.id
            )));
        }
        out.insert(id.clone());
    }
    Ok((!out.is_empty()).then_some(out))
}

/// `ports`: row 1, recorded while this call holds the probe (ports sampled before are there
/// only while a watch is open).
pub async fn ports(probe: &Arc<Probe>, only: Option<&BTreeSet<String>>) -> Value {
    let _hold = probe.hold();
    probe.ask_params().await;
    probe.snapshot(only).0
}

/// Run one watch: send rows through `send` (`false`: the caller is gone) until it ends after
/// `ttl` ([`TTL`] for a watch), and return its last row. `cancel` ends it at once (a newer
/// watch of the same caller took its place).
pub async fn run<F, Fut>(
    probe: Arc<Probe>,
    only: Option<BTreeSet<String>>,
    period: Duration,
    ttl: Duration,
    mut cancel: watch::Receiver<bool>,
    mut send: F,
) -> Option<Value>
where
    F: FnMut(Value) -> Fut,
    Fut: Future<Output = bool>,
{
    let _hold = probe.hold();
    let mut end = probe.end.subscribe();
    let mut wake = probe.wake.subscribe();
    wake.borrow_and_update();
    probe.ask_params().await;
    let (first, mut seen) = probe.snapshot(only.as_ref());
    if let Some(why) = *end.borrow_and_update() {
        return last_row(why);
    }
    if !send(first).await {
        return None;
    }
    let ttl = Instant::now() + ttl;
    let mut last = Instant::now();
    // the earliest time the next row of changes may go
    let mut next = Instant::now();
    loop {
        tokio::select! {
            r = end.changed() => {
                return match r {
                    Ok(()) => (*end.borrow_and_update()).and_then(last_row),
                    Err(_) => None,
                };
            }
            _ = cancel.changed() => return None,
            _ = tokio::time::sleep_until(ttl) => return None,
            _ = tokio::time::sleep_until(last + HEARTBEAT) => {
                if !send(row(None, BTreeMap::new())).await {
                    return None;
                }
                last = Instant::now();
            }
            r = wake.changed() => {
                if r.is_err() {
                    return None;
                }
                // one row per period: what changes meanwhile goes with it, the latest winning
                if Instant::now() < next {
                    tokio::select! {
                        r = end.changed() => {
                            return match r {
                                Ok(()) => (*end.borrow_and_update()).and_then(last_row),
                                Err(_) => None,
                            };
                        }
                        _ = cancel.changed() => return None,
                        _ = tokio::time::sleep_until(next) => {}
                    }
                }
                let (changes, s) = probe.changes(seen, only.as_ref());
                seen = s;
                if let Some(r) = changes {
                    if !send(r).await {
                        return None;
                    }
                    last = Instant::now();
                    next = last + period;
                }
            }
        }
    }
}

/// The open watches of a site, for the caps: at most `per_flow` on one flow and `per_site` in
/// all ([`MAX_PER_FLOW`] and [`MAX_PER_SITE`] by default). Previews use it with the subject in
/// place of the flow (`crate::preview`).
pub struct Watches {
    inner: Mutex<Reg>,
    per_flow: usize,
    per_site: usize,
    what: &'static str,
}

impl Default for Watches {
    fn default() -> Self {
        Self::with_caps(MAX_PER_FLOW, MAX_PER_SITE, "watches")
    }
}

#[derive(Default)]
struct Reg {
    next: u64,
    list: Vec<Entry>,
}

struct Entry {
    id: u64,
    flow: String,
    sub: String,
    cancel: watch::Sender<bool>,
}

/// One registered watch: dropping it frees its place.
pub struct Ticket {
    id: u64,
    reg: Arc<Watches>,
    cancel: watch::Receiver<bool>,
}

impl Ticket {
    /// Changes when a newer watch of the same caller takes this one's place.
    pub fn cancelled(&self) -> watch::Receiver<bool> {
        self.cancel.clone()
    }
}

impl Drop for Ticket {
    fn drop(&mut self) {
        self.reg.lock().list.retain(|e| e.id != self.id);
    }
}

impl Watches {
    /// A registry with these caps; `what` names its entries in a `busy` error.
    pub fn with_caps(per_flow: usize, per_site: usize, what: &'static str) -> Self {
        Self {
            inner: Mutex::new(Reg::default()),
            per_flow,
            per_site,
            what,
        }
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, Reg> {
        self.inner.lock().unwrap_or_else(|p| p.into_inner())
    }

    /// End every registered entry (the engine stops).
    pub fn cancel_all(&self) {
        for e in self.lock().list.drain(..) {
            e.cancel.send_replace(true);
        }
    }

    /// Open watches on `flow` (all flows: `None`).
    pub fn count(&self, flow: Option<&str>) -> usize {
        self.lock()
            .list
            .iter()
            .filter(|e| flow.is_none_or(|f| e.flow == f))
            .count()
    }

    /// Register a watch of `sub` on `flow`. At a cap the oldest watch of the same caller (on
    /// that flow, or on the site) ends to make room: the engine cannot see a caller that went
    /// away without a word, and an editor opens its watch again on every start. A cap full of
    /// other callers' watches is `busy`.
    pub fn open(self: &Arc<Self>, flow: &str, sub: &str) -> Result<Ticket, LinkError> {
        let (per_flow, per_site, noun) = (self.per_flow, self.per_site, self.what);
        let mut r = self.lock();
        let busy = |what: &str| {
            LinkError::new(
                Status::Busy,
                format!("{what}: no more {noun} (at most {per_flow} each, {per_site} per site)"),
            )
        };
        if r.list.iter().filter(|e| e.flow == flow).count() >= per_flow {
            let pos = r
                .list
                .iter()
                .position(|e| e.flow == flow && e.sub == sub)
                .ok_or_else(|| busy(flow))?;
            let old = r.list.remove(pos);
            old.cancel.send_replace(true);
        }
        if r.list.len() >= per_site {
            let pos = r
                .list
                .iter()
                .position(|e| e.sub == sub)
                .ok_or_else(|| busy("site"))?;
            let old = r.list.remove(pos);
            old.cancel.send_replace(true);
        }
        r.next += 1;
        let id = r.next;
        let (tx, rx) = watch::channel(false);
        r.list.push(Entry {
            id,
            flow: flow.to_owned(),
            sub: sub.to_owned(),
            cancel: tx,
        });
        Ok(Ticket {
            id,
            reg: self.clone(),
            cancel: rx,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tokio::sync::mpsc;

    fn def() -> FlowDef {
        let n = |kv: &[(&str, Value)]| {
            Value::Map(
                kv.iter()
                    .map(|(k, v)| ((*k).to_owned(), v.clone()))
                    .collect(),
            )
        };
        crate::def::parse(&n(&[
            ("id", Value::from("f")),
            (
                "nodes",
                n(&[
                    (
                        "r",
                        n(&[
                            ("type", Value::from("round")),
                            ("precision", Value::UInt(2)),
                        ]),
                    ),
                    (
                        "t",
                        n(&[
                            ("type", Value::from("timer")),
                            ("period_ms", Value::UInt(100)),
                        ]),
                    ),
                ]),
            ),
        ]))
        .unwrap()
    }

    fn m(v: f64) -> Msg {
        Msg::new(Value::Float(v), Quality::Good, 1)
    }

    fn get<'a>(v: &'a Value, path: &[&str]) -> Option<&'a Value> {
        path.iter().try_fold(v, |v, k| match v {
            Value::Map(m) => m.get(*k),
            _ => None,
        })
    }

    fn pair(v: f64) -> Value {
        Value::Array(vec![Value::Float(v), Value::UInt(0)])
    }

    #[test]
    fn records_only_while_held() {
        let p = Probe::new(&def());
        assert!(!p.on());
        // nobody records without a watch (run_node checks `on`); a hold turns it on
        let h = p.hold();
        assert!(p.on());
        p.record(
            "r",
            Some(("in".into(), Value::Float(1.5), Quality::Good)),
            &[("out".into(), m(1.5))],
            None,
        );
        let (snap, seq) = p.snapshot(None);
        assert_eq!(get(&snap, &["snapshot"]), Some(&Value::Bool(true)));
        assert_eq!(get(&snap, &["nodes", "r", "in", "in"]), Some(&pair(1.5)));
        assert_eq!(get(&snap, &["nodes", "r", "out", "out"]), Some(&pair(1.5)));
        // parameters from the config and their defaults
        assert_eq!(
            get(&snap, &["nodes", "r", "params", "precision"]),
            Some(&Value::UInt(2))
        );
        assert_eq!(
            get(&snap, &["nodes", "t", "params", "period_ms"]),
            Some(&Value::UInt(100))
        );
        assert_eq!(
            get(&snap, &["nodes", "t", "in"]),
            Some(&Value::Map(BTreeMap::new()))
        );
        // the latest value wins; an unchanged one is not a change
        p.record("r", None, &[("out".into(), m(2.0))], None);
        p.record("r", None, &[("out".into(), m(3.0))], None);
        p.record(
            "r",
            Some(("in".into(), Value::Float(1.5), Quality::Good)),
            &[],
            None,
        );
        let live = BTreeMap::from([("precision".to_owned(), Value::UInt(4))]);
        p.record("r", None, &[], Some(&live));
        let (ch, seq2) = p.changes(seq, None);
        let ch = ch.unwrap();
        assert_eq!(get(&ch, &["snapshot"]), Some(&Value::Bool(false)));
        assert_eq!(get(&ch, &["nodes", "r", "out", "out"]), Some(&pair(3.0)));
        assert_eq!(get(&ch, &["nodes", "r", "in"]), None, "in did not change");
        assert_eq!(
            get(&ch, &["nodes", "r", "params", "precision"]),
            Some(&Value::UInt(4))
        );
        assert_eq!(get(&ch, &["nodes", "t"]), None);
        assert_eq!(p.changes(seq2, None).0, None);
        // a filter leaves the other nodes out
        let only = BTreeSet::from(["t".to_owned()]);
        assert_eq!(p.changes(seq, Some(&only)).0, None);
        let (snap, _) = p.snapshot(Some(&only));
        assert_eq!(get(&snap, &["nodes", "r"]), None);
        drop(h);
        assert!(!p.on());
    }

    /// Rows over a paused clock: snapshot, changes at most `max_hz` (latest wins), a heartbeat
    /// after 10 s, the redeploy row last.
    #[tokio::test(start_paused = true)]
    async fn rows_pace_beat_and_end() {
        let p = Probe::new(&def());
        let (tx, mut rx) = mpsc::unbounded_channel::<Value>();
        let (_cancel_tx, cancel) = watch::channel(false);
        let task = tokio::spawn(run(
            p.clone(),
            None,
            Duration::from_millis(500),
            TTL,
            cancel,
            move |v| {
                let tx = tx.clone();
                async move { tx.send(v).is_ok() }
            },
        ));
        let first = rx.recv().await.unwrap();
        assert_eq!(get(&first, &["snapshot"]), Some(&Value::Bool(true)));
        assert!(p.on(), "the watch holds the probe open");
        let t0 = Instant::now();
        p.record("r", None, &[("out".into(), m(1.0))], None);
        let a = rx.recv().await.unwrap();
        assert_eq!(get(&a, &["nodes", "r", "out", "out"]), Some(&pair(1.0)));
        // three changes inside one period: one row, the latest value
        p.record("r", None, &[("out".into(), m(2.0))], None);
        tokio::time::sleep(Duration::from_millis(100)).await;
        p.record("r", None, &[("out".into(), m(3.0))], None);
        p.record("r", None, &[("out".into(), m(4.0))], None);
        let b = rx.recv().await.unwrap();
        assert!(
            t0.elapsed() >= Duration::from_millis(500),
            "paced: {:?}",
            t0.elapsed()
        );
        assert_eq!(get(&b, &["nodes", "r", "out", "out"]), Some(&pair(4.0)));
        // nothing for 10 s: a heartbeat
        let t1 = Instant::now();
        let hb = rx.recv().await.unwrap();
        assert!(t1.elapsed() >= HEARTBEAT - Duration::from_millis(600));
        assert_eq!(get(&hb, &["nodes"]), Some(&Value::Map(BTreeMap::new())));
        assert_eq!(get(&hb, &["snapshot"]), None);
        // a redeploy ends it with its version
        p.end(End::Redeployed(7));
        let last = task.await.unwrap().unwrap();
        assert_eq!(get(&last, &["redeployed"]), Some(&Value::UInt(7)));
        assert!(!p.on(), "the watch let go of the probe");
    }

    #[tokio::test(start_paused = true)]
    async fn ttl_and_cancel_end_a_watch() {
        let p = Probe::new(&def());
        let (cancel_tx, cancel) = watch::channel(false);
        let rows = Arc::new(Mutex::new(0usize));
        let n = rows.clone();
        let send = move |_v: Value| {
            let n = n.clone();
            async move {
                *n.lock().unwrap() += 1;
                true
            }
        };
        let t0 = Instant::now();
        let last = run(
            p.clone(),
            None,
            Duration::from_millis(250),
            TTL,
            cancel.clone(),
            send.clone(),
        )
        .await;
        assert_eq!(last, None);
        assert!(t0.elapsed() >= TTL);
        // a snapshot and a heartbeat every 10 s (the last one may meet the ttl)
        let beats = (TTL.as_secs() / HEARTBEAT.as_secs()) as usize;
        let n = *rows.lock().unwrap();
        assert!(n == beats || n == beats + 1, "{n} rows");
        let task = tokio::spawn(run(
            p.clone(),
            None,
            Duration::from_millis(250),
            TTL,
            cancel,
            send,
        ));
        tokio::time::sleep(Duration::from_secs(1)).await;
        cancel_tx.send_replace(true);
        assert_eq!(task.await.unwrap(), None);
        // a watch of a flow that is removed ends without a row
        let (_c, cancel) = watch::channel(false);
        let task = tokio::spawn(run(
            p.clone(),
            None,
            Duration::from_millis(250),
            TTL,
            cancel,
            |_| async { true },
        ));
        tokio::time::sleep(Duration::from_secs(1)).await;
        p.end(End::Gone);
        assert_eq!(task.await.unwrap(), None);
    }

    /// ADR 0038 §5: a preview's sinks go with the snapshot and with change rows, the latest per
    /// node; a row of sinks alone is a change row.
    #[test]
    fn sinks_in_rows() {
        let p = Probe::new(&def());
        let _h = p.hold();
        let (snap, seq) = p.snapshot(None);
        assert_eq!(get(&snap, &["sinks"]), None, "no sink acted yet");
        p.sink("r", SinkOp::Set, "wy/s/downstream/l/x/~set", Value::UInt(1));
        p.sink("r", SinkOp::Set, "wy/s/downstream/l/x/~set", Value::UInt(2));
        let (ch, seq2) = p.changes(seq, None);
        let ch = ch.expect("a row of sinks alone");
        assert_eq!(get(&ch, &["snapshot"]), Some(&Value::Bool(false)));
        assert_eq!(get(&ch, &["nodes"]), Some(&Value::Map(BTreeMap::new())));
        let Some(Value::Array(sinks)) = get(&ch, &["sinks"]) else {
            panic!("sinks: {ch:?}")
        };
        assert_eq!(sinks.len(), 1, "the latest per node");
        assert_eq!(get(&sinks[0], &["value"]), Some(&Value::UInt(2)));
        assert_eq!(get(&sinks[0], &["op"]), Some(&Value::from("set")));
        assert_eq!(get(&sinks[0], &["node"]), Some(&Value::from("r")));
        assert_eq!(p.changes(seq2, None).0, None);
        // the snapshot holds every sink's latest; `nodes` filters them
        assert!(get(&p.snapshot(None).0, &["sinks"]).is_some());
        let only = BTreeSet::from(["t".to_owned()]);
        assert_eq!(get(&p.snapshot(Some(&only)).0, &["sinks"]), None);
    }

    #[test]
    fn values_stay_a_moment_after_the_last_watch() {
        let p = Probe::new(&def());
        let h = p.hold();
        p.record("r", None, &[("out".into(), m(1.0))], None);
        drop(h);
        let h = p.hold();
        let (snap, _) = p.snapshot(None);
        assert_eq!(get(&snap, &["nodes", "r", "out", "out"]), Some(&pair(1.0)));
        drop(h);
        // older than KEEP: cleared when the next watch opens
        p.lock().idle_since = Some(Instant::now() - KEEP - Duration::from_secs(1));
        let _h = p.hold();
        let (snap, _) = p.snapshot(None);
        assert_eq!(
            get(&snap, &["nodes", "r", "out"]),
            Some(&Value::Map(BTreeMap::new()))
        );
    }

    #[test]
    fn caps_per_flow_and_site() {
        let w = Arc::new(Watches::default());
        let mut a: Vec<Ticket> = (0..MAX_PER_FLOW)
            .map(|_| w.open("f", "user:a").unwrap())
            .collect();
        assert_eq!(w.count(Some("f")), MAX_PER_FLOW);
        // another caller: busy
        let e = w.open("f", "user:b").err().unwrap();
        assert_eq!(e.status, Status::Busy);
        // the same caller again: its oldest watch ends
        let oldest = a[0].cancelled();
        let _new = w.open("f", "user:a").unwrap();
        assert!(*oldest.borrow(), "the oldest watch was told to end");
        assert_eq!(w.count(Some("f")), MAX_PER_FLOW);
        drop(a.remove(0));
        assert_eq!(
            w.count(Some("f")),
            MAX_PER_FLOW,
            "a dropped evicted ticket frees nothing twice"
        );
        drop(a.pop());
        assert_eq!(w.count(Some("f")), MAX_PER_FLOW - 1);
        // the site: 64 at most
        let mut rest: Vec<Ticket> = Vec::new();
        let mut i = 0;
        while w.count(None) < MAX_PER_SITE {
            rest.push(w.open(&format!("g{}", i / MAX_PER_FLOW), "user:c").unwrap());
            i += 1;
        }
        assert_eq!(w.open("h", "user:b").err().unwrap().status, Status::Busy);
        assert!(
            w.open("h", "user:c").is_ok(),
            "the same caller's oldest watch makes room"
        );
    }

    #[test]
    fn arguments() {
        let d = def();
        let args = |kv: &[(&str, Value)]| {
            Value::Map(
                kv.iter()
                    .map(|(k, v)| ((*k).to_owned(), v.clone()))
                    .collect(),
            )
        };
        assert_eq!(period(&args(&[])).unwrap(), Duration::from_millis(250));
        assert_eq!(
            period(&args(&[("max_hz", Value::UInt(20))])).unwrap(),
            Duration::from_millis(50)
        );
        assert!(period(&args(&[("max_hz", Value::UInt(21))])).is_err());
        assert!(period(&args(&[("max_hz", Value::UInt(0))])).is_err());
        assert_eq!(only(&args(&[]), &d).unwrap(), None);
        assert_eq!(
            only(&args(&[("nodes", Value::Array(vec![]))]), &d).unwrap(),
            None
        );
        let one = only(
            &args(&[("nodes", Value::Array(vec![Value::from("r")]))]),
            &d,
        )
        .unwrap();
        assert_eq!(one, Some(BTreeSet::from(["r".to_owned()])));
        assert!(only(
            &args(&[("nodes", Value::Array(vec![Value::from("zz")]))]),
            &d
        )
        .is_err());
    }
}
