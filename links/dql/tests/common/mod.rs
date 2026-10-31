//! `SimHost`: the DQL link on a `BufferHost` with a tree of other links in memory. Lists answer
//! from that tree, subscriptions get its values, sink calls are recorded and answered `ok`.
//! Each event's commands are applied as the portable runtime does; an event the host would fail
//! (over 1 000 commands) panics the test.

#![allow(dead_code)]

use std::collections::{BTreeMap, HashMap, VecDeque};
use std::sync::{Arc, Mutex};

use wyrm_core::{NodeMeta, Perm, Quality, Sample, Status, TypeCode, Value};
use wyrm_link_api::buffer::{store_cost, BufferHost, Command, Counts, Limits, Services};
use wyrm_link_api::{App, AppError, ConnId, ListChange, ReqId, SubId, TimerId, Who};
use wyrm_link_dql::Dql;

pub const SITE: &str = "wy/s";

#[derive(Default)]
struct Shared {
    now_us: u64,
    store: HashMap<String, Vec<u8>>,
}

struct Sim(Arc<Mutex<Shared>>);

impl Services for Sim {
    fn now_us(&self) -> u64 {
        self.0.lock().unwrap().now_us
    }
    fn store_get(&self, key: &str) -> Option<Vec<u8>> {
        self.0.lock().unwrap().store.get(key).cloned()
    }
    fn store_used(&self) -> u64 {
        let s = self.0.lock().unwrap();
        s.store
            .iter()
            .map(|(k, v)| store_cost(k.len(), v.len()))
            .sum()
    }
    fn store_keys(&self) -> usize {
        self.0.lock().unwrap().store.len()
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

#[allow(clippy::large_enum_variant)]
enum Ev {
    List(u64, String, ListChange),
    Value(u64, String, Sample),
    Reply(u64, Result<Value, AppError>),
}

pub struct SimHost {
    buf: BufferHost,
    shared: Arc<Mutex<Shared>>,
    pub app: Option<Dql>,
    /// Other links' nodes (the world the queries read).
    pub world: BTreeMap<String, NodeMeta>,
    pub values: BTreeMap<String, Value>,
    /// The link's own nodes and their values.
    pub nodes: BTreeMap<String, (NodeMeta, Option<Value>)>,
    timers: BTreeMap<u64, u64>,
    pub subs: BTreeMap<u64, String>,
    pub lists: BTreeMap<u64, String>,
    /// Sink calls: key, action (`None` = set), value.
    pub calls: Vec<(String, Option<String>, Value)>,
    queue: VecDeque<Ev>,
    pub max_cmds: usize,
}

pub fn folder() -> NodeMeta {
    NodeMeta::default()
}

pub fn number() -> NodeMeta {
    NodeMeta {
        ty: Some(TypeCode::Number),
        ..NodeMeta::default()
    }
}

pub fn writer() -> Who {
    Who {
        subject: Some("user:op".into()),
        grants: vec![("wy/s/downstream/dql/**".into(), Perm::Write)],
        authority: Some(vec![("wy/s/**".into(), Perm::Write)]),
    }
}

pub fn engineer() -> Who {
    Who {
        subject: Some("user:eng".into()),
        grants: vec![("wy/s/downstream/dql/**".into(), Perm::Config)],
        authority: Some(vec![("wy/s/**".into(), Perm::Config)]),
    }
}

pub fn map(pairs: &[(&str, Value)]) -> Value {
    Value::Map(
        pairs
            .iter()
            .map(|(k, v)| ((*k).to_owned(), v.clone()))
            .collect(),
    )
}

pub fn s(v: &str) -> Value {
    Value::Str(v.into())
}

impl SimHost {
    pub fn new() -> Self {
        let shared = Arc::new(Mutex::new(Shared {
            now_us: 1_800_000_000_000_000,
            ..Shared::default()
        }));
        let limits = Limits {
            store_bytes: 4 << 20,
            ..Limits::default()
        };
        Self {
            buf: BufferHost::new(
                Box::new(Sim(shared.clone())),
                limits,
                Counts::default(),
                1,
                SITE.into(),
            ),
            shared,
            app: None,
            world: BTreeMap::new(),
            values: BTreeMap::new(),
            nodes: BTreeMap::new(),
            timers: BTreeMap::new(),
            subs: BTreeMap::new(),
            lists: BTreeMap::new(),
            calls: Vec::new(),
            queue: VecDeque::new(),
            max_cmds: 0,
        }
    }

    pub fn now(&self) -> u64 {
        self.shared.lock().unwrap().now_us
    }

    /// A tree of `n` folders with one number each under `wy/s/downstream/mock`.
    pub fn with_mock(mut self, n: usize) -> Self {
        self.world.insert("wy/s/downstream/mock".into(), folder());
        for i in 0..n {
            self.world
                .insert(format!("wy/s/downstream/mock/d{i}"), folder());
            self.world
                .insert(format!("wy/s/downstream/mock/d{i}/temp"), number());
            self.values.insert(
                format!("wy/s/downstream/mock/d{i}/temp"),
                Value::Int(i as i64),
            );
        }
        self
    }

    fn counts(&self) -> Counts {
        Counts {
            timers: self.timers.len(),
            subs: self.subs.len(),
            lists: self.lists.len(),
            inflight: 0,
        }
    }

    fn children(&self, key: &str) -> Vec<(String, NodeMeta)> {
        let p = format!("{key}/");
        self.world
            .iter()
            .filter_map(|(k, m)| {
                let rest = k.strip_prefix(&p)?;
                (!rest.contains('/')).then(|| (rest.to_owned(), m.clone()))
            })
            .collect()
    }

    fn apply(&mut self) {
        let cmds = self.buf.finish().expect("the host would fail this event");
        self.max_cmds = self.max_cmds.max(cmds.len());
        let now = self.now();
        for c in cmds {
            match c {
                Command::DeclareNode(p, m) => {
                    let v = self.nodes.remove(&p).and_then(|(_, v)| v);
                    self.nodes.insert(p, (m, v));
                }
                Command::RemoveNode(p) => {
                    let below = format!("{p}/");
                    self.nodes.retain(|k, _| *k != p && !k.starts_with(&below));
                }
                Command::Update(p, smp) => {
                    if let Some(n) = self.nodes.get_mut(&p) {
                        n.1 = Some(smp.v);
                    } else {
                        panic!("update of an undeclared node {p}");
                    }
                }
                Command::SetTimer(TimerId(id), ms) => {
                    self.timers.insert(id, now + ms * 1000);
                }
                Command::CancelTimer(TimerId(id)) => {
                    self.timers.remove(&id);
                }
                Command::StorePut(k, v) => {
                    self.shared.lock().unwrap().store.insert(k, v);
                }
                Command::StoreDelete(k) => {
                    self.shared.lock().unwrap().store.remove(&k);
                }
                Command::Subscribe(SubId(id), key) => {
                    let prefix = key.trim_end_matches("/**").to_owned();
                    for (k, v) in &self.values {
                        if k == &prefix || k.starts_with(&format!("{prefix}/")) {
                            self.queue
                                .push_back(Ev::Value(id, k.clone(), sample(v.clone(), now)));
                        }
                    }
                    self.subs.insert(id, key);
                }
                Command::List(SubId(id), key, _) => {
                    let snap = self.children(&key);
                    self.queue
                        .push_back(Ev::List(id, key.clone(), ListChange::Refreshed(snap)));
                    self.lists.insert(id, key);
                }
                Command::Unsubscribe(SubId(id)) => {
                    self.subs.remove(&id);
                    self.lists.remove(&id);
                }
                Command::Set(ReqId(id), key, v) => {
                    self.calls.push((key, None, v));
                    self.queue.push_back(Ev::Reply(id, Ok(Value::Null)));
                }
                Command::Invoke(ReqId(id), key, action, args) => {
                    self.calls.push((key, Some(action), args));
                    self.queue.push_back(Ev::Reply(id, Ok(Value::Null)));
                }
                Command::DeclareAction(..) | Command::Log(..) => {}
            }
        }
        self.buf.set_counts(self.counts());
    }

    pub fn start(&mut self) {
        let app = Dql::start(&mut self.buf, Value::Null).expect("start");
        self.app = Some(app);
        self.apply();
        self.settle();
    }

    /// A restart: a new instance on the same store; the tree of the old one is kept as the
    /// runtime keeps it until the sweep.
    pub fn restart(&mut self) {
        self.app = None;
        self.timers.clear();
        self.subs.clear();
        self.lists.clear();
        self.queue.clear();
        self.buf.set_counts(self.counts());
        self.start();
    }

    /// Delivers queued events and due timers until nothing is left (time does not move).
    pub fn settle(&mut self) {
        loop {
            if let Some(ev) = self.queue.pop_front() {
                let app = self.app.as_mut().expect("started");
                match ev {
                    Ev::List(id, key, c) => {
                        if self.lists.contains_key(&id) {
                            app.on_list(&mut self.buf, SubId(id), &key, c);
                        }
                    }
                    Ev::Value(id, key, smp) => {
                        if self.subs.contains_key(&id) {
                            app.on_value(&mut self.buf, SubId(id), &key, smp);
                        }
                    }
                    Ev::Reply(id, r) => app.on_reply(&mut self.buf, ReqId(id), r),
                }
                self.apply();
                continue;
            }
            let now = self.now();
            let due = self
                .timers
                .iter()
                .find(|(_, t)| **t <= now)
                .map(|(id, _)| *id);
            match due {
                Some(id) => {
                    self.timers.remove(&id);
                    self.app
                        .as_mut()
                        .expect("started")
                        .on_timer(&mut self.buf, TimerId(id));
                    self.apply();
                }
                None => return,
            }
        }
    }

    /// Moves the clock and runs what became due.
    pub fn advance_ms(&mut self, ms: u64) {
        self.shared.lock().unwrap().now_us += ms * 1000;
        self.settle();
    }

    pub fn invoke(
        &mut self,
        path: &str,
        action: &str,
        args: Value,
        who: &Who,
    ) -> Result<Value, AppError> {
        let r =
            self.app
                .as_mut()
                .expect("started")
                .on_invoke(&mut self.buf, path, action, args, who);
        self.apply();
        self.settle();
        r
    }

    pub fn set(&mut self, path: &str, v: Value) -> Result<(), AppError> {
        self.set_as(path, v, &writer())
    }

    pub fn set_as(&mut self, path: &str, v: Value, who: &Who) -> Result<(), AppError> {
        let r = self
            .app
            .as_mut()
            .expect("started")
            .on_set(&mut self.buf, path, v, who);
        self.apply();
        self.settle();
        r
    }

    /// A value of another link changes: subscriptions that cover it get it.
    pub fn put_value(&mut self, key: &str, v: Value) {
        self.values.insert(key.to_owned(), v.clone());
        let now = self.now();
        for (id, k) in &self.subs {
            let prefix = k.trim_end_matches("/**");
            if key == prefix || key.starts_with(&format!("{prefix}/")) {
                self.queue
                    .push_back(Ev::Value(*id, key.to_owned(), sample(v.clone(), now)));
            }
        }
        self.settle();
    }

    /// A node of another link appears.
    pub fn add_node(&mut self, key: &str, meta: NodeMeta) {
        self.world.insert(key.to_owned(), meta.clone());
        let (parent, name) = key.rsplit_once('/').unwrap();
        for (id, k) in &self.lists {
            if k == parent {
                self.queue.push_back(Ev::List(
                    *id,
                    k.clone(),
                    ListChange::Added(name.into(), meta.clone()),
                ));
            }
        }
        self.settle();
    }

    /// The value `<q>/table` (a query with `publish`).
    pub fn published(&self, q: &str) -> Vec<Value> {
        match self
            .nodes
            .get(&format!("{q}/table"))
            .and_then(|(_, v)| v.clone())
        {
            Some(Value::Array(a)) => a,
            None => Vec::new(),
            Some(v) => panic!("table is {v:?}"),
        }
    }

    /// The rows `get_table` gives `who`.
    pub fn table_as(&mut self, q: &str, who: &Who) -> Vec<Value> {
        match self.invoke(q, "get_table", Value::Null, who) {
            Ok(Value::Map(m)) => match m.get("rows") {
                Some(Value::Array(a)) => a.clone(),
                _ => Vec::new(),
            },
            _ => Vec::new(),
        }
    }

    /// The rows `get_table` gives an engineer (who may read the whole site).
    pub fn table(&mut self, q: &str) -> Vec<Value> {
        self.table_as(q, &engineer())
    }

    pub fn attr(&self, q: &str, a: &str) -> Value {
        self.nodes
            .get(q)
            .and_then(|(m, _)| m.attr.as_ref())
            .and_then(|m| m.get(a).cloned())
            .unwrap_or(Value::Null)
    }

    pub fn store_has(&self, k: &str) -> bool {
        self.shared.lock().unwrap().store.contains_key(k)
    }
}

fn sample(v: Value, t: u64) -> Sample {
    Sample {
        v,
        q: Quality::Good,
        t,
    }
}
