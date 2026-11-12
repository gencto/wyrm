//! Flow execution (wiki "Виконання, backpressure, стан"): a task per node,
//! one bounded inbox per node fed by its incoming edges, push model,
//! overflow policy per flow, panics isolated to the flow. Every run counts into the
//! flow's [`FlowStats`] (ADR 0045), which the engine publishes in `~val.stats`.

use crate::artifacts::Artifacts;
use crate::def::{FlowDef, Overflow};
use crate::nodes::{self, EchoOf, Io, Msg, Node, Out, Ports};
use crate::watch::Probe;
use std::collections::{BTreeMap, HashMap, HashSet, VecDeque};
use std::panic::AssertUnwindSafe;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use tokio::sync::{mpsc, watch, Notify};
use tokio::task::JoinHandle;
use tracing::warn;
use wyrm_core::{Quality, Value};
use wyrm_link_sdk::now_us;

/// Counters of one deployed flow (ADR 0045, spec 06 0.2.31 `~val.stats`). Atomics only
/// (`Relaxed`): a node task adds to them with no lock and no allocation. The engine makes
/// a new one at each deploy and each `start`/`reload`, and keeps it across a restart after
/// a node panic (that restart counts in `restarts`).
#[derive(Default)]
pub struct FlowStats {
    /// Samples the nodes took in: each sample from an edge, and each sample a source
    /// (`subscribe`, `liveliness`, `const`) received. A command's or a reader's answer, a
    /// trigger and a node's other internal messages are not counted.
    pub samples_in: AtomicU64,
    /// Samples the nodes sent on an output that has at least one edge.
    pub samples_out: AtomicU64,
    /// Samples the inboxes dropped by the flow's overflow policy.
    pub dropped: AtomicU64,
    /// Restarts after a node panic.
    pub restarts: AtomicU64,
    /// Events `sent`, `ok` and `error` of the `invoke`/`set` blocks.
    pub commands_sent: AtomicU64,
    pub commands_ok: AtomicU64,
    pub commands_error: AtomicU64,
    /// Wall time (µs) when a node last took in a sample, 0 before the first one.
    pub last_sample_t: AtomicU64,
}

/// A copy of [`FlowStats`] at one moment: what the engine compares and publishes.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct StatsSnapshot {
    pub samples_in: u64,
    pub samples_out: u64,
    pub dropped: u64,
    pub restarts: u64,
    pub commands_sent: u64,
    pub commands_ok: u64,
    pub commands_error: u64,
    pub last_sample_t: u64,
}

impl FlowStats {
    pub fn snapshot(&self) -> StatsSnapshot {
        let get = |a: &AtomicU64| a.load(Ordering::Relaxed);
        StatsSnapshot {
            samples_in: get(&self.samples_in),
            samples_out: get(&self.samples_out),
            dropped: get(&self.dropped),
            restarts: get(&self.restarts),
            commands_sent: get(&self.commands_sent),
            commands_ok: get(&self.commands_ok),
            commands_error: get(&self.commands_error),
            last_sample_t: get(&self.last_sample_t),
        }
    }

    fn took_in(&self) {
        self.samples_in.fetch_add(1, Ordering::Relaxed);
        self.last_sample_t.store(now_us(), Ordering::Relaxed);
    }

    /// The events of a command block in what one call sent.
    fn command_events(&self, out: &Out) {
        for (port, _) in &out.0 {
            let c = match port.as_str() {
                "sent" => &self.commands_sent,
                "ok" => &self.commands_ok,
                "error" => &self.commands_error,
                _ => continue,
            };
            c.fetch_add(1, Ordering::Relaxed);
        }
    }
}

/// An inbox sample that counts in `samples_in`: one from an edge (no `__` port), or one a
/// source received (`__src…` of `subscribe`, `liveliness`, `const`; `__lost…`, the owner
/// gone). Answers (`__result…`, `__sent`), `__read` and `__trigger` are not samples.
fn counts_in(port: &str) -> bool {
    match port.strip_prefix("__") {
        None => true,
        Some(p) => p.starts_with("src") || p.starts_with("lost"),
    }
}

/// Bounded queue of `(port, msg)` with the flow's overflow policy.
pub struct Inbox {
    q: Mutex<VecDeque<(String, Msg)>>,
    data: Notify,
    space: Notify,
    cap: usize,
    overflow: Overflow,
    pub dropped: AtomicU64,
    stats: Arc<FlowStats>,
}

impl Inbox {
    fn new(cap: usize, overflow: Overflow, stats: Arc<FlowStats>) -> Arc<Self> {
        Arc::new(Self {
            q: Mutex::new(VecDeque::new()),
            data: Notify::new(),
            space: Notify::new(),
            cap,
            overflow,
            dropped: AtomicU64::new(0),
            stats,
        })
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, VecDeque<(String, Msg)>> {
        self.q.lock().unwrap_or_else(|p| p.into_inner())
    }

    /// Non-blocking push (sources): `block` degrades to `drop_newest`.
    pub fn push_now(&self, port: &str, m: Msg) {
        let mut q = self.lock();
        if q.len() >= self.cap {
            self.dropped.fetch_add(1, Ordering::Relaxed);
            self.stats.dropped.fetch_add(1, Ordering::Relaxed);
            match self.overflow {
                Overflow::DropOldest => {
                    q.pop_front();
                }
                Overflow::DropNewest | Overflow::Block => return,
            }
        }
        q.push_back((port.to_owned(), m));
        drop(q);
        self.data.notify_one();
    }

    /// Node-to-node push: `block` waits for space.
    async fn push(&self, port: &str, m: Msg) {
        if self.overflow != Overflow::Block {
            return self.push_now(port, m);
        }
        loop {
            let wait = self.space.notified();
            {
                let mut q = self.lock();
                if q.len() < self.cap {
                    q.push_back((port.to_owned(), m));
                    drop(q);
                    self.data.notify_one();
                    return;
                }
            }
            wait.await;
        }
    }

    /// Nothing waits in the queue.
    fn is_empty(&self) -> bool {
        self.lock().is_empty()
    }

    async fn pop(&self) -> (String, Msg) {
        loop {
            let wait = self.data.notified();
            if let Some(item) = self.lock().pop_front() {
                self.space.notify_one();
                return item;
            }
            wait.await;
        }
    }
}

/// Latest state of each stateful node: `node → (config hash, state)`.
pub type States = Arc<Mutex<BTreeMap<String, (u32, Value)>>>;

pub struct Running {
    stop: watch::Sender<bool>,
    flush: watch::Sender<u64>,
    tasks: Vec<JoinHandle<()>>,
    pub states: States,
    pub inboxes: BTreeMap<String, Arc<Inbox>>,
}

type Route = Vec<(Arc<Inbox>, String)>;

/// The echo outputs of one node that an edge reads (ADR 0038 §1); the others are never built.
#[derive(Default)]
struct Echoes {
    /// Inputs whose samples go out again under the input's name.
    inputs: HashSet<String>,
    /// Parameters whose effective value goes out under the parameter's name.
    params: Vec<String>,
}

impl Running {
    /// Ask nodes to write their state into [`Running::states`].
    pub fn flush(&self) {
        self.flush.send_modify(|g| *g += 1);
    }

    /// Stop accepting, drain for at most 1 s, stop the tasks. When it returns, every node
    /// task has ended: a task cut at the deadline is awaited after its abort, as an aborted
    /// task is dropped only later by the runtime.
    pub async fn stop(mut self) -> States {
        self.flush();
        let _ = self.stop.send(true);
        let deadline = tokio::time::Instant::now() + std::time::Duration::from_secs(1);
        for mut t in std::mem::take(&mut self.tasks) {
            if tokio::time::timeout_at(deadline, &mut t).await.is_err() {
                t.abort();
                let _ = t.await;
            }
        }
        self.states.clone()
    }
}

impl Drop for Running {
    /// A run dropped without [`Running::stop`] (a preview cut at the engine's stop) takes
    /// its node tasks with it instead of leaving them running.
    fn drop(&mut self) {
        for t in &self.tasks {
            t.abort();
        }
    }
}

/// Start `def`. `restored`: states of unchanged nodes (same id and hash).
/// `io_for(node)` builds each node's I/O handle. A node panic is reported
/// on `panics` and stops this run. `wasm` nodes load from `artifacts`. The node
/// tasks record into `probe` while a watch holds it open (ADR 0038 §3). `mode`: a deployed
/// flow, or a preview whose sinks only report (ADR 0038 §5). The run counts into `stats`
/// (ADR 0045).
#[allow(clippy::too_many_arguments)]
pub fn start(
    def: &FlowDef,
    ports: &BTreeMap<String, Ports>,
    restored: &BTreeMap<String, (u32, Value)>,
    io_for: impl Fn(&str, nodes::Inject) -> Io,
    panics: mpsc::UnboundedSender<String>,
    artifacts: Option<&Artifacts>,
    probe: Arc<Probe>,
    mode: &nodes::Mode,
    stats: Arc<FlowStats>,
) -> Result<Running, String> {
    let inboxes: BTreeMap<String, Arc<Inbox>> = def
        .nodes
        .keys()
        .map(|id| {
            (
                id.clone(),
                Inbox::new(def.policy.queue, def.policy.overflow, stats.clone()),
            )
        })
        .collect();
    let mut routes: HashMap<String, HashMap<String, Route>> = HashMap::new();
    let mut echoes: HashMap<String, Echoes> = HashMap::new();
    for e in &def.edges {
        let from = &ports[&e.from.node];
        let out = from.canon_output(&e.from.port);
        if from.outputs.iter().all(|(n, _)| *n != out) {
            if let Some(echo) = from.echo(&out) {
                let mine = echoes.entry(e.from.node.clone()).or_default();
                match echo.of {
                    EchoOf::Input => {
                        mine.inputs.insert(out.clone());
                    }
                    EchoOf::Param if !mine.params.contains(&out) => mine.params.push(out.clone()),
                    EchoOf::Param => {}
                }
            }
        }
        routes
            .entry(e.from.node.clone())
            .or_default()
            .entry(out)
            .or_default()
            .push((inboxes[&e.to.node].clone(), e.to.port.clone()));
    }
    let states: States = Arc::new(Mutex::new(BTreeMap::new()));
    let (stop, stop_rx) = watch::channel(false);
    let (flush, flush_rx) = watch::channel(0u64);
    let wired: std::collections::HashSet<&str> =
        def.edges.iter().map(|e| e.to.node.as_str()).collect();
    let mut built: Vec<(String, u32, bool, Box<dyn Node>)> = Vec::new();
    for (id, n) in &def.nodes {
        let mut node = nodes::build_with(&n.ty, &def.id, id, &n.cfg, artifacts, mode)?;
        // no edge into it: a pure block calculates once at the start (spec 06 0.2.30)
        if !wired.contains(id.as_str()) {
            node.unwired();
        }
        if let Some((hash, st)) = restored.get(id) {
            if *hash == n.hash {
                node.restore(st);
            }
        }
        let command = matches!(n.ty.as_str(), "invoke" | "set");
        built.push((id.clone(), n.hash, command, node));
    }
    let mut tasks = Vec::new();
    for (id, hash, command, node) in built {
        let inbox = inboxes[&id].clone();
        let inj_box = inbox.clone();
        let inject: nodes::Inject = Arc::new(move |port: &str, m: Msg| inj_box.push_now(port, m));
        let io = io_for(&id, inject);
        tasks.push(tokio::spawn(run_node(
            id.clone(),
            hash,
            node,
            inbox,
            routes.remove(&id).unwrap_or_default(),
            echoes.remove(&id).unwrap_or_default(),
            io,
            states.clone(),
            stop_rx.clone(),
            flush_rx.clone(),
            panics.clone(),
            probe.clone(),
            Counted {
                stats: stats.clone(),
                command,
            },
        )));
    }
    Ok(Running {
        stop,
        flush,
        tasks,
        states,
        inboxes,
    })
}

/// Where a node task counts (ADR 0045): the flow's stats, and whether its node is a
/// command block whose events count as commands.
struct Counted {
    stats: Arc<FlowStats>,
    command: bool,
}

#[allow(clippy::too_many_arguments)]
async fn run_node(
    id: String,
    hash: u32,
    mut node: Box<dyn Node>,
    inbox: Arc<Inbox>,
    routes: HashMap<String, Route>,
    echoes: Echoes,
    io: Io,
    states: States,
    mut stop: watch::Receiver<bool>,
    mut flush: watch::Receiver<u64>,
    panics: mpsc::UnboundedSender<String>,
    probe: Arc<Probe>,
    counted: Counted,
) {
    let stats = &counted.stats;
    let save = |node: &dyn Node| {
        let state = std::panic::catch_unwind(AssertUnwindSafe(|| node.state()));
        if let Ok(Some(st)) = state {
            states
                .lock()
                .unwrap_or_else(|p| p.into_inner())
                .insert(id.clone(), (hash, st));
        }
    };
    if std::panic::catch_unwind(AssertUnwindSafe(|| node.start(&io))).is_err() {
        let _ = panics.send(format!("nodes.{id}: panic in start"));
        return;
    }
    // asks from here on are seen: an ask sent once this task is alive is never missed
    let mut asks = probe.asks();
    asks.borrow_and_update();
    // the operands' constants are the inputs' values from the start
    for (port, v) in node.seeds() {
        probe.record(&id, Some((&port, &v, Quality::Good)), &[], None);
    }
    let _alive = Alive::new(&probe, &id);
    // An ask is answered once the inbox is empty, so what start queued (a variable's
    // value) is recorded and routed before the answer (a preview's snapshot has it).
    let mut pending_ask: Option<u64> = None;
    let statics = probe.statics(&id);
    // The parameters' change counter as their echo outputs and the recorder last saw it.
    let rev_now = |node: &dyn Node| node.live_params().map(|(r, _)| r);
    let mut echo_rev = rev_now(node.as_ref());
    let mut rec_rev = echo_rev;
    let mut echoed: BTreeMap<String, Value> = BTreeMap::new();
    if !echoes.params.is_empty() {
        // a parameter's echo sends once at start
        let mut out = Out::default();
        let now = now_us();
        for p in &echoes.params {
            let v = node
                .live_params()
                .and_then(|(_, m)| m.get(p).cloned())
                .or_else(|| statics.get(p).cloned());
            if let Some(v) = v {
                out.emit(p, Msg::new(v.clone(), Quality::Good, now).at_start());
                echoed.insert(p.clone(), v);
            }
        }
        probe.record(&id, None, &out.0, None);
        route(&routes, out, stats).await;
    }
    let clock = |p: std::time::Duration, first: tokio::time::Instant| {
        let mut iv = tokio::time::interval_at(first, p);
        iv.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
        iv
    };
    // every call into a node runs under the panic guard, the small ones too: a node that
    // panics while it says its clock ends its flow's run as any other panic does
    let clock_of = |node: &dyn Node| {
        std::panic::catch_unwind(AssertUnwindSafe(|| {
            (node.tick_every(), node.first_tick_now())
        }))
    };
    let Ok((mut period, at_once)) = clock_of(node.as_ref()) else {
        let _ = panics.send(format!("nodes.{id}: panic in tick_every"));
        return;
    };
    let mut tick = period.map(|p| {
        let first = tokio::time::Instant::now();
        clock(p, if at_once { first } else { first + p })
    });
    // A tick at the start is born at the start, and so is what a node sends while it handles
    // a sample that was (ADR 0040 §2): the mark goes on with everything such a call sends. The
    // same holds for a sample made of typed constants (spec 06 0.2.30).
    let mut start_tick = at_once;
    loop {
        let mut out = Out::default();
        let mut born_at_start = false;
        let mut of_constants = false;
        let ok = tokio::select! {
            (port, m) = inbox.pop() => {
                born_at_start = m.start;
                of_constants = m.constant;
                if counts_in(&port) {
                    stats.took_in();
                }
                if !port.starts_with("__") {
                    // an input's echo goes out before the node handles the sample
                    if !echoes.inputs.is_empty() && echoes.inputs.contains(&port) {
                        out.emit(&port, m.clone());
                    }
                    // the input's slot, before the node takes the sample (no copy of it)
                    probe.record(&id, Some((&port, &m.v, m.q)), &[], None);
                }
                std::panic::catch_unwind(AssertUnwindSafe(|| node.input(&port, m, &io, &mut out))).is_ok()
            }
            _ = async { match tick.as_mut() { Some(t) => { t.tick().await; } None => std::future::pending::<()>().await } } => {
                born_at_start = std::mem::take(&mut start_tick);
                std::panic::catch_unwind(AssertUnwindSafe(|| node.tick(now_us(), &mut out))).is_ok()
            }
            Ok(()) = asks.changed() => {
                pending_ask = Some(*asks.borrow_and_update());
                true
            }
            _ = flush.changed() => { save(node.as_ref()); true }
            _ = stop.changed() => { save(node.as_ref()); return; }
        };
        if !ok {
            warn!(node = %id, "flow node panicked");
            let _ = panics.send(format!("nodes.{id}: panic"));
            return;
        }
        if counted.command && !out.0.is_empty() {
            stats.command_events(&out);
        }
        if born_at_start {
            for (_, m) in &mut out.0 {
                m.start = true;
                m.constant |= of_constants;
            }
        }
        if !echoes.params.is_empty() {
            if let Some((rev, live)) = node.live_params() {
                if Some(rev) != echo_rev {
                    echo_rev = Some(rev);
                    let now = now_us();
                    for p in &echoes.params {
                        if let Some(v) = live.get(p) {
                            if echoed.get(p) != Some(v) {
                                out.emit(p, Msg::new(v.clone(), Quality::Good, now));
                                echoed.insert(p.clone(), v.clone());
                            }
                        }
                    }
                }
            }
        }
        // the last sample of every port, watched or not (spec 06 0.2.18)
        let live = node.live_params().filter(|(r, _)| Some(*r) != rec_rev);
        if let Some((r, _)) = live {
            rec_rev = Some(r);
        }
        if !out.0.is_empty() || live.is_some() {
            probe.record(&id, None, &out.0, live.map(|(_, m)| m));
        }
        route(&routes, out, stats).await;
        // a parameter on its port may change the clock (`timer.period_ms`, `delay.ms`,
        // `window.size_s`, `alarm.delay_s`): the new one starts one period from now
        let Ok((now_every, _)) = clock_of(node.as_ref()) else {
            warn!(node = %id, "flow node panicked");
            let _ = panics.send(format!("nodes.{id}: panic in tick_every"));
            return;
        };
        if now_every != period {
            start_tick = false;
            period = now_every;
            tick = period.map(|p| clock(p, tokio::time::Instant::now() + p));
        }
        if let Some(gen) = pending_ask {
            if inbox.is_empty() {
                pending_ask = None;
                probe.answer(&id, gen, node.live_params().map(|(_, m)| m));
                rec_rev = rev_now(node.as_ref());
            }
        }
    }
}

/// Send what a node emitted to the inboxes its edges name; a sample with an edge counts in
/// `samples_out`.
async fn route(routes: &HashMap<String, Route>, out: Out, stats: &FlowStats) {
    for (port, m) in out.0 {
        if let Some(targets) = routes.get(&port) {
            stats.samples_out.fetch_add(1, Ordering::Relaxed);
            for (target, in_port) in targets {
                target.push(in_port, m.clone()).await;
            }
        }
    }
}

/// A node task, known to the probe while it runs (an opening watch waits for its parameters).
struct Alive<'a>(&'a Probe, &'a str);

impl<'a> Alive<'a> {
    fn new(probe: &'a Probe, id: &'a str) -> Self {
        probe.alive(id, true);
        Self(probe, id)
    }
}

impl Drop for Alive<'_> {
    fn drop(&mut self) {
        self.0.alive(self.1, false);
    }
}
