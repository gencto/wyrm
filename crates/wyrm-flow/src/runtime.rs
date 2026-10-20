//! Flow execution (wiki "Виконання, backpressure, стан"): a task per node,
//! one bounded inbox per node fed by its incoming edges, push model,
//! overflow policy per flow, panics isolated to the flow.

use crate::artifacts::Artifacts;
use crate::def::{FlowDef, Overflow};
use crate::nodes::{self, Io, Msg, Node, Out, Ports};
use std::collections::{BTreeMap, HashMap, VecDeque};
use std::panic::AssertUnwindSafe;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use tokio::sync::{mpsc, watch, Notify};
use tokio::task::JoinHandle;
use tracing::warn;
use wyrm_core::Value;
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
            q: Mutex::new(VecDeque::with_capacity(cap.min(1024))),
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
/// on `panics` and stops this run. `wasm` nodes load from `artifacts`.
pub fn start(
    def: &FlowDef,
    ports: &BTreeMap<String, Ports>,
    restored: &BTreeMap<String, (u32, Value)>,
    io_for: impl Fn(&str, nodes::Inject) -> Io,
    panics: mpsc::UnboundedSender<String>,
    artifacts: Option<&Artifacts>,
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
    for e in &def.edges {
        let out = ports[&e.from.node].canon_output(&e.from.port);
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
        let mut node = nodes::build_with(&n.ty, &def.id, id, &n.cfg, artifacts)?;
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
            io,
            states.clone(),
            stop_rx.clone(),
            flush_rx.clone(),
            panics.clone(),
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
    io: Io,
    states: States,
    mut stop: watch::Receiver<bool>,
    mut flush: watch::Receiver<u64>,
    panics: mpsc::UnboundedSender<String>,
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
    let mut tick = node.tick_every().map(|p| {
        let mut iv = tokio::time::interval(p);
        iv.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
        iv
    });
    loop {
        let mut out = Out::default();
        let ok = tokio::select! {
            (port, m) = inbox.pop() => {
                std::panic::catch_unwind(AssertUnwindSafe(|| node.input(&port, m, &io, &mut out))).is_ok()
            }
            _ = async { match tick.as_mut() { Some(t) => { t.tick().await; } None => std::future::pending::<()>().await } } => {
                std::panic::catch_unwind(AssertUnwindSafe(|| node.tick(now_us(), &mut out))).is_ok()
            }
            _ = flush.changed() => { save(node.as_ref()); true }
            _ = stop.changed() => { save(node.as_ref()); return; }
        };
        if !ok {
            warn!(node = %id, "flow node panicked");
            let _ = panics.send(format!("nodes.{id}: panic"));
            return;
        }
        for (port, m) in out.0 {
            if let Some(targets) = routes.get(&port) {
                for (target, in_port) in targets {
                    target.push(in_port, m.clone()).await;
                }
            }
        }
    }
}
