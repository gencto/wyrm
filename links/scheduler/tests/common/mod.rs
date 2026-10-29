//! `SimHost`: the scheduler on a `BufferHost` with a settable wall clock, a monotonic clock for
//! timers and an in-memory store. It applies each event's commands as the portable runtime does
//! (store writes, the tree, timers) and refuses what the runtime would refuse (a child under a
//! value, the root or a hidden path, more than `max_nodes`) by panicking, so a test fails where
//! the real host would restart the instance.

#![allow(dead_code)]

use std::collections::{BTreeMap, HashMap};
use std::sync::{Arc, Mutex};

use wyrm_core::{ActionMeta, NodeMeta, Perm, Quality, Sample, Status, Value};
use wyrm_link_api::buffer::{store_cost, BufferHost, Command, Counts, Limits, Services};
use wyrm_link_api::{App, AppError, ConnId, Host, ReqId, SubId, TimerId, Who};
use wyrm_link_scheduler::Scheduler;

pub const SITE: &str = "wy/s";
/// The embedded scheduler's store (`store_mb = 64`).
pub const STORE_BYTES: u64 = 64 * 1024 * 1024;

#[derive(Default)]
struct Shared {
    wall_us: u64,
    store: HashMap<String, Vec<u8>>,
    /// Quota used by others, added to the store's own entries.
    extra_used: u64,
    /// Wall time each `now_us` read moves on: time spent inside an event.
    tick_us: u64,
}

struct SimServices(Arc<Mutex<Shared>>);

impl SimServices {
    fn lock(&self) -> std::sync::MutexGuard<'_, Shared> {
        self.0.lock().unwrap()
    }
}

impl Services for SimServices {
    fn now_us(&self) -> u64 {
        let mut s = self.lock();
        let t = s.wall_us;
        s.wall_us += s.tick_us;
        t
    }
    fn store_get(&self, key: &str) -> Option<Vec<u8>> {
        self.lock().store.get(key).cloned()
    }
    fn store_used(&self) -> u64 {
        let s = self.lock();
        s.extra_used
            + s.store
                .iter()
                .map(|(k, v)| store_cost(k.len(), v.len()))
                .sum::<u64>()
    }
    fn store_keys(&self) -> usize {
        self.lock().store.len()
    }
    fn may(&self, _key: &str, _perm: Perm) -> bool {
        true
    }
    fn tcp_connect(&mut self, _a: &str, _p: u16, _t: u32) -> Result<ConnId, AppError> {
        Err(AppError::new(Status::PermissionDenied, "no network"))
    }
    fn tcp_send(&mut self, _c: ConnId, _d: &[u8]) -> Result<(), AppError> {
        Err(AppError::new(Status::NotFound, "no connection"))
    }
    fn tcp_recv(&mut self, _c: ConnId, _m: u32, _t: u32) -> Result<Vec<u8>, AppError> {
        Err(AppError::new(Status::NotFound, "no connection"))
    }
    fn tcp_close(&mut self, _c: ConnId) {}
}

/// One declared node.
#[derive(Debug, Clone)]
pub struct Node {
    pub meta: NodeMeta,
    pub value: Option<Value>,
}

pub struct SimHost {
    buf: BufferHost,
    shared: Arc<Mutex<Shared>>,
    limits: Limits,
    app: Option<Scheduler>,
    params: Value,
    mono_ms: u64,
    /// Live timers: id → due on the monotonic clock.
    timers: BTreeMap<u64, u64>,
    /// The last `SetTimer`: its id and delay.
    pub armed: Option<(TimerId, u64)>,
    pub nodes: BTreeMap<String, Node>,
    pub root_actions: BTreeMap<String, ActionMeta>,
    /// Commands of every event since the last [`SimHost::take_log`].
    pub log: Vec<Command>,
    /// The most commands one event returned.
    pub max_cmds: usize,
    /// Events run (start, actions, sets, timers).
    pub events: usize,
    /// The most wall time one event took (with [`SimHost::set_tick`]).
    pub max_event_us: u64,
    /// How long a `0` ms timer waits in the host's queue before it fires.
    pub queue_latency_ms: u64,
    /// Live subscriptions: id → key.
    pub subs: BTreeMap<u64, String>,
    /// Sets without a reply yet: id → key and value.
    pub sets: BTreeMap<u64, (String, Value)>,
    /// The most sets without a reply after any event.
    pub max_unreplied: usize,
}

impl SimHost {
    /// A host at `wall_us` with an empty store; the app is not started.
    pub fn new(wall_us: u64) -> Self {
        let shared = Arc::new(Mutex::new(Shared {
            wall_us,
            ..Default::default()
        }));
        let limits = Limits {
            store_bytes: STORE_BYTES,
            ..Limits::default()
        };
        let buf = BufferHost::new(
            Box::new(SimServices(shared.clone())),
            limits.clone(),
            Counts::default(),
            1,
            SITE.into(),
        );
        SimHost {
            buf,
            shared,
            limits,
            app: None,
            params: Value::Null,
            mono_ms: 0,
            timers: BTreeMap::new(),
            armed: None,
            nodes: BTreeMap::new(),
            root_actions: BTreeMap::new(),
            log: Vec::new(),
            max_cmds: 0,
            events: 0,
            max_event_us: 0,
            queue_latency_ms: 0,
            subs: BTreeMap::new(),
            sets: BTreeMap::new(),
            max_unreplied: 0,
        }
    }

    /// `Scheduler::start` with `params`; its commands are applied only when it succeeds.
    pub fn start(&mut self, params: Value) -> Result<Vec<Command>, AppError> {
        self.params = params.clone();
        self.buf.set_counts(self.counts());
        let r = Scheduler::start(&mut self.buf, params);
        let cmds = self
            .buf
            .finish()
            .expect("start: the host would fail the event");
        self.events += 1;
        match r {
            Ok(app) => {
                self.app = Some(app);
                self.apply(&cmds);
                Ok(cmds)
            }
            Err(e) => Err(e),
        }
    }

    /// A new instance over the same store and clocks: the tree and the timers are gone.
    pub fn restart(&mut self) -> Result<Vec<Command>, AppError> {
        self.app = None;
        self.nodes.clear();
        self.root_actions.clear();
        self.timers.clear();
        self.armed = None;
        self.subs.clear();
        self.sets.clear();
        let params = self.params.clone();
        self.start(params)
    }

    fn counts(&self) -> Counts {
        Counts {
            timers: self.timers.len(),
            subs: self.subs.len(),
            inflight: self.sets.len(),
        }
    }

    /// One event of the app: its commands are applied (as the runtime does, also when the app
    /// answers with an error) and returned.
    pub fn event<R>(
        &mut self,
        f: impl FnOnce(&mut Scheduler, &mut dyn Host) -> R,
    ) -> (R, Vec<Command>) {
        self.buf.set_counts(self.counts());
        let began = self.now_us();
        let app = self.app.as_mut().expect("the app is started");
        let r = f(app, &mut self.buf);
        let took = self.now_us() - began;
        self.max_event_us = self.max_event_us.max(took);
        let cmds = self.buf.finish().expect("the host would fail the event");
        self.events += 1;
        self.apply(&cmds);
        (r, cmds)
    }

    pub fn invoke(&mut self, path: &str, action: &str, args: Value) -> Result<Value, AppError> {
        self.invoke_cmds(path, action, args).0
    }

    pub fn invoke_cmds(
        &mut self,
        path: &str,
        action: &str,
        args: Value,
    ) -> (Result<Value, AppError>, Vec<Command>) {
        let who = Who {
            subject: Some("user:test".into()),
            grants: vec![],
        };
        self.invoke_as(&who, path, action, args)
    }

    pub fn invoke_as(
        &mut self,
        who: &Who,
        path: &str,
        action: &str,
        args: Value,
    ) -> (Result<Value, AppError>, Vec<Command>) {
        self.event(|app, h| app.on_invoke(h, path, action, args, who))
    }

    /// Answers the set `req` (as the target link's responder would).
    pub fn reply(&mut self, req: u64, result: Result<Value, AppError>) -> Vec<Command> {
        assert!(
            self.sets.remove(&req).is_some(),
            "set {req} has no reply due"
        );
        self.event(|app, h| app.on_reply(h, ReqId(req), result)).1
    }

    /// The sets without a reply, oldest first: id, key, value.
    pub fn unreplied(&self) -> Vec<(u64, String, Value)> {
        self.sets
            .iter()
            .map(|(id, (k, v))| (*id, k.clone(), v.clone()))
            .collect()
    }

    /// A good sample of `key` to every live subscription on it; the number of subscriptions.
    pub fn deliver(&mut self, key: &str, v: Value) -> usize {
        self.deliver_q(key, v, Quality::Good)
    }

    /// A sample of `key` with quality `q` to every live subscription on it.
    pub fn deliver_q(&mut self, key: &str, v: Value, q: Quality) -> usize {
        let ids: Vec<u64> = self
            .subs
            .iter()
            .filter(|(_, k)| *k == key)
            .map(|(id, _)| *id)
            .collect();
        for id in &ids {
            let sample = Sample {
                v: v.clone(),
                q,
                t: self.now_us(),
            };
            self.event(|app, h| app.on_value(h, SubId(*id), key, sample));
        }
        ids.len()
    }

    /// Live subscriptions on `key`.
    pub fn subscribed(&self, key: &str) -> usize {
        self.subs.values().filter(|k| *k == key).count()
    }

    /// Answers every set `ok` and reads its value back on the point, until none waits; the
    /// `0` ms continuations run in between.
    pub fn confirm_all(&mut self) {
        loop {
            self.settle();
            let due = self.unreplied();
            if due.is_empty() {
                return;
            }
            for (id, key, v) in due {
                self.reply(id, Ok(Value::Null));
                self.deliver(&key, v);
            }
        }
    }

    pub fn set(&mut self, path: &str, value: Value) -> Result<(), AppError> {
        let who = Who::default();
        self.event(|app, h| app.on_set(h, path, value, &who)).0
    }

    pub fn app(&self) -> &Scheduler {
        self.app.as_ref().expect("the app is started")
    }

    pub fn now_us(&self) -> u64 {
        self.shared.lock().unwrap().wall_us
    }

    /// Moves both clocks by `ms`, firing every timer that falls due on the way, at its time.
    pub fn advance(&mut self, ms: u64) {
        let end = self.mono_ms + ms;
        let mut fired = 0usize;
        loop {
            let next = self
                .timers
                .iter()
                .filter(|(_, due)| **due <= end)
                .min_by_key(|(id, due)| (**due, **id))
                .map(|(id, due)| (*id, *due));
            let Some((id, due)) = next else { break };
            self.move_mono(due);
            self.timers.remove(&id);
            self.event(|app, h| app.on_timer(h, TimerId(id)));
            fired += 1;
            assert!(fired < 1_000_000, "timers keep firing");
        }
        self.move_mono(end);
    }

    /// Runs the `0` ms continuations that are due now.
    pub fn settle(&mut self) {
        self.advance(0);
    }

    /// Moves the wall clock to `wall_us` (forward), firing timers on the way.
    pub fn advance_to(&mut self, wall_us: u64) {
        let now = self.now_us();
        assert!(wall_us >= now, "advance_to goes forward");
        self.advance((wall_us - now) / 1000);
    }

    fn move_mono(&mut self, to: u64) {
        let d = to - self.mono_ms;
        self.mono_ms = to;
        self.shared.lock().unwrap().wall_us += d * 1000;
    }

    /// Moves the wall clock only (an NTP step or a resume from sleep).
    pub fn step_clock(&mut self, delta_ms: i64) {
        let mut s = self.shared.lock().unwrap();
        s.wall_us = s.wall_us.checked_add_signed(delta_ms * 1000).unwrap();
    }

    /// Each wall clock read inside an event moves the clock on by `us` (the app's own work
    /// takes time).
    pub fn set_tick(&mut self, us: u64) {
        self.shared.lock().unwrap().tick_us = us;
    }

    pub fn set_extra_used(&mut self, bytes: u64) {
        self.shared.lock().unwrap().extra_used = bytes;
    }

    pub fn store_used(&self) -> u64 {
        SimServices(self.shared.clone()).store_used()
    }

    pub fn store_get(&self, key: &str) -> Option<Vec<u8>> {
        self.shared.lock().unwrap().store.get(key).cloned()
    }

    pub fn store_put(&mut self, key: &str, value: Vec<u8>) {
        self.shared
            .lock()
            .unwrap()
            .store
            .insert(key.to_owned(), value);
    }

    pub fn store_delete(&mut self, key: &str) {
        self.shared.lock().unwrap().store.remove(key);
    }

    pub fn store_keys(&self) -> Vec<String> {
        let mut k: Vec<_> = self.shared.lock().unwrap().store.keys().cloned().collect();
        k.sort();
        k
    }

    pub fn take_log(&mut self) -> Vec<Command> {
        std::mem::take(&mut self.log)
    }

    pub fn node(&self, path: &str) -> &Node {
        self.nodes
            .get(path)
            .unwrap_or_else(|| panic!("no node {path:?}"))
    }

    pub fn has(&self, path: &str) -> bool {
        self.nodes.contains_key(path)
    }

    pub fn value(&self, path: &str) -> Option<Value> {
        self.node(path).value.clone()
    }

    pub fn attr(&self, path: &str, key: &str) -> Value {
        self.node(path)
            .meta
            .attr_value(key)
            .cloned()
            .unwrap_or_else(|| panic!("{path}: no attr {key}"))
    }

    pub fn action(&self, path: &str, name: &str) -> ActionMeta {
        if path.is_empty() {
            return self.root_actions[name].clone();
        }
        self.node(path)
            .meta
            .actions
            .as_ref()
            .and_then(|a| a.get(name))
            .cloned()
            .unwrap_or_else(|| panic!("{path}: no action {name}"))
    }

    fn apply(&mut self, cmds: &[Command]) {
        self.max_cmds = self.max_cmds.max(cmds.len());
        for c in cmds {
            self.apply_one(c);
        }
        self.log.extend_from_slice(cmds);
        self.max_unreplied = self.max_unreplied.max(self.sets.len());
    }

    fn apply_one(&mut self, c: &Command) {
        let hidden = |p: &str| p.split('/').any(|s| s.starts_with('.'));
        match c {
            Command::DeclareNode(p, m) => {
                assert!(!p.is_empty() && !hidden(p), "{p:?} belongs to the host");
                if let Some((parent, _)) = p.rsplit_once('/') {
                    let parent = self
                        .nodes
                        .get(parent)
                        .unwrap_or_else(|| panic!("parent of {p} not declared"));
                    assert!(parent.meta.ty.is_none(), "parent of {p} is a leaf");
                }
                if let Some(old) = self.nodes.get_mut(p) {
                    let mut m = m.clone();
                    if m.actions.is_none() {
                        m.actions = old.meta.actions.clone();
                    }
                    old.meta = m;
                } else {
                    assert!(
                        self.nodes.len() < self.limits.max_nodes,
                        "too many nodes (at most {})",
                        self.limits.max_nodes
                    );
                    self.nodes.insert(
                        p.clone(),
                        Node {
                            meta: m.clone(),
                            value: None,
                        },
                    );
                }
            }
            Command::DeclareAction(p, name, a) => {
                if p.is_empty() {
                    self.root_actions.insert(name.clone(), a.clone());
                } else {
                    let n = self
                        .nodes
                        .get_mut(p)
                        .unwrap_or_else(|| panic!("no node {p}"));
                    n.meta
                        .actions
                        .get_or_insert_with(BTreeMap::new)
                        .insert(name.clone(), a.clone());
                }
            }
            Command::RemoveNode(p) => {
                let sub = format!("{p}/");
                self.nodes.retain(|k, _| k != p && !k.starts_with(&sub));
            }
            Command::Update(p, s) => {
                assert!(!p.is_empty() && !hidden(p), "{p:?} belongs to the host");
                let n = self
                    .nodes
                    .get_mut(p)
                    .unwrap_or_else(|| panic!("update of {p}: no node"));
                assert!(n.meta.ty.is_some(), "{p} is a container: no ~val");
                n.value = Some(s.v.clone());
            }
            Command::SetTimer(id, ms) => {
                let latency = if *ms == 0 { self.queue_latency_ms } else { 0 };
                self.timers.insert(id.0, self.mono_ms + ms + latency);
                self.armed = Some((*id, *ms));
            }
            Command::CancelTimer(id) => {
                self.timers.remove(&id.0);
            }
            Command::StorePut(k, v) => {
                self.shared
                    .lock()
                    .unwrap()
                    .store
                    .insert(k.clone(), v.clone());
            }
            Command::StoreDelete(k) => {
                self.shared.lock().unwrap().store.remove(k);
            }
            Command::Subscribe(id, k) => {
                self.subs.insert(id.0, k.clone());
            }
            Command::Unsubscribe(id) => {
                self.subs.remove(&id.0);
            }
            Command::Set(id, k, v) => {
                self.sets.insert(id.0, (k.clone(), v.clone()));
            }
            _ => {}
        }
    }

    /// Live timers (set, not cancelled, not fired).
    pub fn live_timers(&self) -> usize {
        self.timers.len()
    }
}

/// `Value::Map` from pairs.
pub fn map<const N: usize>(entries: [(&str, Value); N]) -> Value {
    Value::Map(
        entries
            .into_iter()
            .map(|(k, v)| (k.to_owned(), v))
            .collect(),
    )
}

pub fn text(s: &str) -> Value {
    Value::Str(s.to_owned())
}

/// Microseconds of an RFC 3339 instant.
pub fn at(rfc3339: &str) -> u64 {
    let t: jiff::Timestamp = rfc3339.parse().unwrap();
    u64::try_from(t.as_microsecond()).unwrap()
}

/// 2026-10-29T07:00Z, where the tests start.
pub fn t0() -> u64 {
    at("2026-10-29T07:00:00Z")
}

/// A started scheduler at [`t0`] with no params.
pub fn started() -> SimHost {
    let mut h = SimHost::new(t0());
    h.start(Value::Null).expect("start");
    h.settle();
    h
}

pub fn is_update(c: &Command, path: &str) -> bool {
    matches!(c, Command::Update(p, _) if p == path)
}

/// The sets among `cmds`: key and value.
pub fn sets_of(cmds: &[Command]) -> Vec<(String, Value)> {
    cmds.iter()
        .filter_map(|c| match c {
            Command::Set(_, k, v) => Some((k.clone(), v.clone())),
            _ => None,
        })
        .collect()
}

pub fn status(r: Result<Value, AppError>) -> (Status, String) {
    let e = r.expect_err("the action is refused");
    (e.status, e.msg)
}
