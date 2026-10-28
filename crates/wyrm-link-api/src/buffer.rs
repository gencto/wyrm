//! [`BufferHost`]: the one command buffer every host uses (ADR 0023).
//!
//! An app acts through the `Host` trait during one event. `BufferHost` records those effects as
//! [`Command`]s. The runtime applies them after the event returns, and drops them all when the event
//! fails. The type is owned and `'static`, so a WASM host can keep it in its `Store`.

use std::collections::{HashMap, HashSet};

use wyrm_core::keyspace;
use wyrm_core::{ActionMeta, NodeMeta, Perm, Sample, Status, Value};

use crate::{AppError, ConnId, Host, Level, ReqId, SubId, TimerId};

fn exhausted(what: &str) -> AppError {
    AppError::new(Status::ResourceExhausted, what)
}

/// One effect of an event, applied by the runtime after the event returns.
#[derive(Debug, Clone, PartialEq)]
pub enum Command {
    DeclareNode(String, NodeMeta),
    DeclareAction(String, String, ActionMeta),
    RemoveNode(String),
    Update(String, Sample),
    /// Timer id and delay in milliseconds.
    SetTimer(TimerId, u64),
    CancelTimer(TimerId),
    StorePut(String, Vec<u8>),
    StoreDelete(String),
    Subscribe(SubId, String),
    Unsubscribe(SubId),
    Set(ReqId, String, Value),
    Invoke(ReqId, String, String, Value),
    Log(Level, String),
}

/// What the runtime gives the buffer: reads and the network, which do not wait for the commit.
pub trait Services {
    fn now_us(&self) -> u64;
    fn store_get(&self, key: &str) -> Option<Vec<u8>>;
    /// Bytes in the link's store now, without this event's pending writes.
    fn store_used(&self) -> u64;
    /// The link holds at least `perm` on `key`.
    fn may(&self, key: &str, perm: Perm) -> bool;
    fn tcp_connect(&mut self, addr: &str, port: u16, timeout_ms: u32) -> Result<ConnId, AppError>;
    fn tcp_send(&mut self, c: ConnId, d: &[u8]) -> Result<(), AppError>;
    fn tcp_recv(&mut self, c: ConnId, max: u32, timeout_ms: u32) -> Result<Vec<u8>, AppError>;
    fn tcp_close(&mut self, c: ConnId);
}

/// Bounds of one link (ADR 0023).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Limits {
    pub max_nodes: usize,
    pub max_timers: usize,
    pub max_subs: usize,
    pub max_inflight: usize,
    pub max_commands: usize,
    pub store_bytes: u64,
}

impl Default for Limits {
    fn default() -> Self {
        Self {
            max_nodes: 10_000,
            max_timers: 1_000,
            max_subs: 1_000,
            max_inflight: 100,
            max_commands: 1_000,
            store_bytes: 1024 * 1024,
        }
    }
}

/// What the link holds now. The runtime owns these numbers and updates them between events.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct Counts {
    pub nodes: usize,
    pub timers: usize,
    pub subs: usize,
    pub inflight: usize,
}

/// A `Host` that records commands. One buffer serves many events: call [`BufferHost::finish`] after each.
pub struct BufferHost {
    services: Box<dyn Services + Send>,
    limits: Limits,
    counts: Counts,
    next_id: u64,
    site_prefix: String,
    // per-event state
    cmds: Vec<Command>,
    failed: Option<AppError>,
    added_nodes: usize,
    added_timers: HashSet<u64>,
    added_subs: HashSet<u64>,
    added_inflight: usize,
    /// Pending store writes: `Some` = put, `None` = delete.
    pending: HashMap<String, Option<Vec<u8>>>,
}

impl BufferHost {
    pub fn new(
        services: Box<dyn Services + Send>,
        limits: Limits,
        counts: Counts,
        next_id: u64,
        site_prefix: String,
    ) -> Self {
        // One trailing `/`, so a match is on a segment boundary: `wy/site/p` is not in `wy/s`.
        let site_prefix = format!("{}/", site_prefix.trim_end_matches('/'));
        Self {
            services,
            limits,
            counts,
            next_id,
            site_prefix,
            cmds: Vec::new(),
            failed: None,
            added_nodes: 0,
            added_timers: HashSet::new(),
            added_subs: HashSet::new(),
            added_inflight: 0,
            pending: HashMap::new(),
        }
    }

    /// Ends the event: returns its commands, or the error when the event went over a bound that
    /// the app could not see (a void call). Clears the per-event state either way.
    pub fn finish(&mut self) -> Result<Vec<Command>, AppError> {
        let cmds = std::mem::take(&mut self.cmds);
        let failed = self.failed.take();
        self.added_nodes = 0;
        self.added_timers.clear();
        self.added_subs.clear();
        self.added_inflight = 0;
        self.pending.clear();
        match failed {
            Some(e) => Err(e),
            None => Ok(cmds),
        }
    }

    /// The next id this buffer hands out. It grows for the life of the runtime.
    pub fn next_id(&self) -> u64 {
        self.next_id
    }

    /// The runtime calls this between events, after it applied the commands.
    pub fn set_counts(&mut self, counts: Counts) {
        self.counts = counts;
    }

    pub fn services_mut(&mut self) -> &mut dyn Services {
        &mut *self.services
    }

    fn id(&mut self) -> u64 {
        let id = self.next_id;
        self.next_id += 1;
        id
    }

    fn fail(&mut self, e: AppError) {
        self.failed.get_or_insert(e);
    }

    /// Room for one more command. At the cap the event is marked failed and the caller drops its command.
    fn room(&mut self) -> Result<(), AppError> {
        if self.cmds.len() >= self.limits.max_commands {
            let e = exhausted("too many commands in one event");
            self.fail(e.clone());
            return Err(e);
        }
        Ok(())
    }

    /// A void command: the buffer keeps it, or marks the event failed when it cannot.
    fn push(&mut self, c: Command) {
        if self.room().is_ok() {
            self.cmds.push(c);
        }
    }

    /// A key a request may name: inside the site, a plain node path (no wildcards, no `.`/`..`),
    /// and within the link's grants. Shape is checked first, so a malformed key never reaches `may`.
    fn check_key(&self, key: &str, perm: Perm) -> Result<(), AppError> {
        let Some(rest) = key.strip_prefix(&self.site_prefix) else {
            return Err(AppError::new(
                Status::PermissionDenied,
                format!("{key} is outside {}", self.site_prefix),
            ));
        };
        let plain = |seg: &str| !matches!(seg, "." | "..") && !seg.contains(['*', '$']);
        if rest.is_empty() || keyspace::validate_path(rest).is_err() || !rest.split('/').all(plain)
        {
            return Err(AppError::new(
                Status::InvalidParameter,
                format!("{key} is not a node key"),
            ));
        }
        if !self.services.may(key, perm) {
            return Err(AppError::new(
                Status::PermissionDenied,
                format!("no grant on {key}"),
            ));
        }
        Ok(())
    }

    fn pending_bytes(&self) -> u64 {
        self.pending
            .iter()
            .filter_map(|(k, v)| v.as_ref().map(|v| (k.len() + v.len()) as u64))
            .sum()
    }

    fn request(&mut self, key: &str, perm: Perm) -> Result<ReqId, AppError> {
        self.check_key(key, perm)?;
        if self.counts.inflight + self.added_inflight >= self.limits.max_inflight {
            return Err(exhausted("too many requests in flight"));
        }
        self.room()?;
        self.added_inflight += 1;
        Ok(ReqId(self.id()))
    }
}

impl Host for BufferHost {
    fn declare_node(&mut self, path: &str, meta: NodeMeta) {
        if self.counts.nodes + self.added_nodes >= self.limits.max_nodes {
            self.fail(exhausted("too many nodes"));
            return;
        }
        if self.room().is_ok() {
            self.added_nodes += 1;
            self.cmds.push(Command::DeclareNode(path.to_owned(), meta));
        }
    }

    fn declare_action(&mut self, path: &str, name: &str, action: ActionMeta) {
        self.push(Command::DeclareAction(
            path.to_owned(),
            name.to_owned(),
            action,
        ));
    }

    fn remove_node(&mut self, path: &str) {
        self.push(Command::RemoveNode(path.to_owned()));
    }

    fn update(&mut self, path: &str, sample: Sample) {
        self.push(Command::Update(path.to_owned(), sample));
    }

    fn now_us(&self) -> u64 {
        self.services.now_us()
    }

    fn set_timer(&mut self, after_ms: u64) -> Result<TimerId, AppError> {
        if self.counts.timers + self.added_timers.len() >= self.limits.max_timers {
            return Err(exhausted("too many timers"));
        }
        self.room()?;
        let id = self.id();
        self.added_timers.insert(id);
        self.cmds.push(Command::SetTimer(TimerId(id), after_ms));
        Ok(TimerId(id))
    }

    fn cancel_timer(&mut self, t: TimerId) {
        self.added_timers.remove(&t.0);
        self.push(Command::CancelTimer(t));
    }

    fn store_get(&self, key: &str) -> Option<Vec<u8>> {
        match self.pending.get(key) {
            Some(v) => v.clone(),
            None => self.services.store_get(key),
        }
    }

    fn store_put(&mut self, key: &str, value: &[u8]) -> Result<(), AppError> {
        let others = self.pending_bytes()
            - self
                .pending
                .get(key)
                .and_then(|v| v.as_ref())
                .map_or(0, |v| (key.len() + v.len()) as u64);
        let new = (key.len() + value.len()) as u64;
        if self
            .services
            .store_used()
            .saturating_add(others)
            .saturating_add(new)
            > self.limits.store_bytes
        {
            return Err(exhausted("store is full"));
        }
        self.room()?;
        self.pending.insert(key.to_owned(), Some(value.to_vec()));
        self.cmds
            .push(Command::StorePut(key.to_owned(), value.to_vec()));
        Ok(())
    }

    fn store_delete(&mut self, key: &str) {
        if self.room().is_ok() {
            self.pending.insert(key.to_owned(), None);
            self.cmds.push(Command::StoreDelete(key.to_owned()));
        }
    }

    fn subscribe(&mut self, key: &str) -> Result<SubId, AppError> {
        self.check_key(key, Perm::Read)?;
        if self.counts.subs + self.added_subs.len() >= self.limits.max_subs {
            return Err(exhausted("too many subscriptions"));
        }
        self.room()?;
        let id = self.id();
        self.added_subs.insert(id);
        self.cmds
            .push(Command::Subscribe(SubId(id), key.to_owned()));
        Ok(SubId(id))
    }

    fn unsubscribe(&mut self, sub: SubId) {
        self.added_subs.remove(&sub.0);
        self.push(Command::Unsubscribe(sub));
    }

    fn set(&mut self, key: &str, value: Value) -> Result<ReqId, AppError> {
        let id = self.request(key, Perm::Write)?;
        self.cmds.push(Command::Set(id, key.to_owned(), value));
        Ok(id)
    }

    fn invoke(&mut self, key: &str, action: &str, args: Value) -> Result<ReqId, AppError> {
        let id = self.request(key, Perm::Read)?;
        self.cmds
            .push(Command::Invoke(id, key.to_owned(), action.to_owned(), args));
        Ok(id)
    }

    fn tcp_connect(&mut self, addr: &str, port: u16, timeout_ms: u32) -> Result<ConnId, AppError> {
        self.services.tcp_connect(addr, port, timeout_ms)
    }

    fn tcp_send(&mut self, c: ConnId, data: &[u8]) -> Result<(), AppError> {
        self.services.tcp_send(c, data)
    }

    fn tcp_recv(&mut self, c: ConnId, max: u32, timeout_ms: u32) -> Result<Vec<u8>, AppError> {
        self.services.tcp_recv(c, max, timeout_ms)
    }

    fn tcp_close(&mut self, c: ConnId) {
        self.services.tcp_close(c);
    }

    fn log(&mut self, level: Level, msg: &str) {
        self.push(Command::Log(level, msg.to_owned()));
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{AppError, ConnId, Host, Level};
    use wyrm_core::{Perm, Quality, Sample, Status, Value};

    struct FakeServices {
        used: u64,
        allow: bool,
    }

    impl Services for FakeServices {
        fn now_us(&self) -> u64 {
            42
        }
        fn store_get(&self, _key: &str) -> Option<Vec<u8>> {
            None
        }
        fn store_used(&self) -> u64 {
            self.used
        }
        fn may(&self, _key: &str, _perm: Perm) -> bool {
            self.allow
        }
        fn tcp_connect(&mut self, _a: &str, _p: u16, _t: u32) -> Result<ConnId, AppError> {
            Ok(ConnId(1))
        }
        fn tcp_send(&mut self, _c: ConnId, _d: &[u8]) -> Result<(), AppError> {
            Ok(())
        }
        fn tcp_recv(&mut self, _c: ConnId, _m: u32, _t: u32) -> Result<Vec<u8>, AppError> {
            Ok(vec![])
        }
        fn tcp_close(&mut self, _c: ConnId) {}
    }

    fn host(used: u64, allow: bool, limits: Limits) -> BufferHost {
        BufferHost::new(
            Box::new(FakeServices { used, allow }),
            limits,
            Counts::default(),
            1,
            "wy/s/".into(),
        )
    }

    fn sample() -> Sample {
        Sample {
            v: Value::Int(1),
            q: Quality::Good,
            t: 0,
        }
    }

    fn exhausted(e: &AppError) -> bool {
        e.status == Status::ResourceExhausted
    }

    #[test]
    fn store_reads_its_own_writes() {
        let mut h = host(0, true, Limits::default());
        h.store_put("a", &[1]).unwrap();
        assert_eq!(h.store_get("a"), Some(vec![1]));
        h.store_delete("a");
        assert_eq!(h.store_get("a"), None);
        let cmds = h.finish().unwrap();
        assert_eq!(cmds.len(), 2);
        // The overlay is gone after finish.
        assert_eq!(h.store_get("a"), None);
    }

    #[test]
    fn store_put_over_quota_is_refused() {
        let limits = Limits {
            store_bytes: 10,
            ..Limits::default()
        };
        let mut h = host(8, true, limits);
        let e = h.store_put("a", &[1, 2, 3]).unwrap_err();
        assert!(exhausted(&e));
        assert!(h.finish().unwrap().is_empty());
    }

    #[test]
    fn store_put_replacing_a_key_counts_the_new_size_once() {
        let limits = Limits {
            store_bytes: 10,
            ..Limits::default()
        };
        let mut h = host(0, true, limits);
        h.store_put("a", &[0; 8]).unwrap();
        h.store_put("a", &[0; 8]).unwrap();
        assert!(h.store_put("b", &[0; 8]).is_err());
    }

    #[test]
    fn bounds_on_timers_and_commands() {
        let limits = Limits {
            max_timers: 1,
            ..Limits::default()
        };
        let mut h = host(0, true, limits);
        let t = h.set_timer(10).unwrap();
        assert!(exhausted(&h.set_timer(10).unwrap_err()));
        h.cancel_timer(t);
        assert!(h.set_timer(10).is_ok());
        h.finish().unwrap();

        let mut h = host(0, true, Limits::default());
        for _ in 0..1001 {
            h.update("p", sample());
        }
        let e = h.finish().unwrap_err();
        assert!(exhausted(&e));
        // The next event starts clean.
        h.update("p", sample());
        assert_eq!(h.finish().unwrap().len(), 1);
    }

    #[test]
    fn counts_from_the_runtime_are_added_to() {
        let limits = Limits {
            max_subs: 2,
            max_inflight: 1,
            ..Limits::default()
        };
        let counts = Counts {
            subs: 2,
            inflight: 1,
            ..Counts::default()
        };
        let mut h = BufferHost::new(
            Box::new(FakeServices {
                used: 0,
                allow: true,
            }),
            limits,
            counts,
            1,
            "wy/s/".into(),
        );
        assert!(exhausted(&h.subscribe("wy/s/x").unwrap_err()));
        assert!(exhausted(&h.set("wy/s/x", Value::Int(1)).unwrap_err()));
        h.set_counts(Counts::default());
        assert!(h.subscribe("wy/s/x").is_ok());
    }

    #[test]
    fn nodes_over_the_bound_fail_the_event() {
        let limits = Limits {
            max_nodes: 1,
            ..Limits::default()
        };
        let mut h = host(0, true, limits);
        h.declare_node("a", Default::default());
        h.declare_node("b", Default::default());
        assert!(exhausted(&h.finish().unwrap_err()));
    }

    #[test]
    fn requests_check_grants_and_site() {
        let mut h = host(0, false, Limits::default());
        let e = h.set("wy/s/x", Value::Int(1)).unwrap_err();
        assert_eq!(e.status, Status::PermissionDenied);
        let mut h = host(0, true, Limits::default());
        let e = h.set("wy/other/x", Value::Int(1)).unwrap_err();
        assert_eq!(e.status, Status::PermissionDenied);
        assert_eq!(
            h.subscribe("wy/other/x").unwrap_err().status,
            Status::PermissionDenied
        );
        let r = h.set("wy/s/x", Value::Int(1)).unwrap();
        let s = h.subscribe("wy/s/x").unwrap();
        let i = h.invoke("wy/s/x", "go", Value::Null).unwrap();
        h.log(Level::Info, "hi");
        let cmds = h.finish().unwrap();
        assert!(matches!(&cmds[0], Command::Set(id, k, _) if *id == r && k == "wy/s/x"));
        assert!(matches!(&cmds[1], Command::Subscribe(id, _) if *id == s));
        assert!(matches!(&cmds[2], Command::Invoke(id, ..) if *id == i));
        assert!(matches!(&cmds[3], Command::Log(Level::Info, _)));
        assert!(r.0 < s.0 && s.0 < i.0);
        assert_eq!(h.next_id(), 4);
    }

    #[test]
    fn request_keys_are_validated() {
        for prefix in ["wy/s", "wy/s/"] {
            let mut h = BufferHost::new(
                Box::new(FakeServices {
                    used: 0,
                    allow: true,
                }),
                Limits::default(),
                Counts::default(),
                1,
                prefix.into(),
            );
            for bad in [
                "wy/s/../other/p",
                "wy/s//p",
                "wy/s/a/*/p",
                "wy/s/a/**",
                "wy/s/a/~set",
                "wy/s/a/$x",
                "wy/s/",
            ] {
                let e = h.set(bad, Value::Int(1)).unwrap_err();
                assert_eq!(e.status, Status::InvalidParameter, "{bad}");
                assert_eq!(
                    h.subscribe(bad).unwrap_err().status,
                    Status::InvalidParameter
                );
                assert_eq!(
                    h.invoke(bad, "a", Value::Null).unwrap_err().status,
                    Status::InvalidParameter
                );
            }
            for outside in ["wy/site/p", "wy/s", "wy/other/p"] {
                let e = h.set(outside, Value::Int(1)).unwrap_err();
                assert_eq!(e.status, Status::PermissionDenied, "{outside}");
            }
            assert!(h.finish().unwrap().is_empty());
            assert!(h.set("wy/s/downstream/plc/p1", Value::Int(1)).is_ok());
            assert_eq!(h.finish().unwrap().len(), 1);
        }
    }
}
