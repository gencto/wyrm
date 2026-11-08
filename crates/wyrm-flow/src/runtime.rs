//! Flow execution (wiki "Виконання, backpressure, стан"): a task per node,
//! one bounded inbox per node fed by its incoming edges, push model,
//! overflow policy per flow, panics isolated to the flow.

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

/// Bounded queue of `(port, msg)` with the flow's overflow policy.
pub struct Inbox {
    q: Mutex<VecDeque<(String, Msg)>>,
    data: Notify,
    space: Notify,
    cap: usize,
    overflow: Overflow,
    pub dropped: AtomicU64,
}

impl Inbox {
    fn new(cap: usize, overflow: Overflow) -> Arc<Self> {
        Arc::new(Self {
            q: Mutex::new(VecDeque::new()),
            data: Notify::new(),
            space: Notify::new(),
            cap,
            overflow,
            dropped: AtomicU64::new(0),
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

    /// Stop accepting, drain for at most 1 s, stop the tasks.
    pub async fn stop(self) -> States {
        self.flush();
        let _ = self.stop.send(true);
        for t in self.tasks {
            let mut t = t;
            if tokio::time::timeout(std::time::Duration::from_secs(1), &mut t)
                .await
                .is_err()
            {
                t.abort();
            }
        }
        self.states
    }
}

/// Start `def`. `restored`: states of unchanged nodes (same id and hash).
/// `io_for(node)` builds each node's I/O handle. A node panic is reported
/// on `panics` and stops this run. `wasm` nodes load from `artifacts`. The node
/// tasks record into `probe` while a watch holds it open (ADR 0038 §3). `mode`: a deployed
/// flow, or a preview whose sinks only report (ADR 0038 §5).
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
) -> Result<Running, String> {
    let inboxes: BTreeMap<String, Arc<Inbox>> = def
        .nodes
        .keys()
        .map(|id| {
            (
                id.clone(),
                Inbox::new(def.policy.queue, def.policy.overflow),
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
    let mut built: Vec<(String, u32, Box<dyn Node>)> = Vec::new();
    for (id, n) in &def.nodes {
        let mut node = nodes::build_with(&n.ty, &def.id, id, &n.cfg, artifacts, mode)?;
        if let Some((hash, st)) = restored.get(id) {
            if *hash == n.hash {
                node.restore(st);
            }
        }
        built.push((id.clone(), n.hash, node));
    }
    let mut tasks = Vec::new();
    for (id, hash, node) in built {
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
) {
    let save = |node: &dyn Node| {
        if let Some(st) = node.state() {
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
                out.emit(p, Msg::new(v.clone(), Quality::Good, now));
                echoed.insert(p.clone(), v);
            }
        }
        probe.record(&id, None, &out.0, None);
        route(&routes, out).await;
    }
    let clock = |p: std::time::Duration, first: tokio::time::Instant| {
        let mut iv = tokio::time::interval_at(first, p);
        iv.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
        iv
    };
    let mut period = node.tick_every();
    let mut tick = period.map(|p| clock(p, tokio::time::Instant::now()));
    loop {
        let mut out = Out::default();
        let ok = tokio::select! {
            (port, m) = inbox.pop() => {
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
        route(&routes, out).await;
        // a parameter on its port may change the clock (`timer.period_ms`, `delay.ms`,
        // `window.size_s`, `alarm.delay_s`): the new one starts one period from now
        let now_every = node.tick_every();
        if now_every != period {
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

/// Send what a node emitted to the inboxes its edges name.
async fn route(routes: &HashMap<String, Route>, out: Out) {
    for (port, m) in out.0 {
        if let Some(targets) = routes.get(&port) {
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
