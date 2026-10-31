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

/// Store quota unit: each entry costs its key and value length rounded up to this, and at least
/// this (one file per key on disk, ADR 0023).
pub const STORE_BLOCK: u64 = 4096;
/// Longest store key, in bytes.
pub const MAX_STORE_KEY_LEN: usize = 256;
/// Keys in one link's store.
pub const MAX_STORE_KEYS: usize = 10_000;
/// Actions on one node.
pub const MAX_ACTIONS: usize = 64;

/// What one store entry counts toward the quota: key and value length in [`STORE_BLOCK`]s,
/// at least one block.
pub fn store_cost(key_len: usize, value_len: usize) -> u64 {
    let n = (key_len as u64).saturating_add(value_len as u64);
    n.div_ceil(STORE_BLOCK).max(1).saturating_mul(STORE_BLOCK)
}

/// An action name: one key segment, not `.` or `..` (it becomes `~act/<name>`).
pub fn check_action_name(name: &str) -> Result<(), AppError> {
    if matches!(name, "." | "..") || keyspace::validate_segment(name).is_err() {
        return Err(AppError::new(
            Status::InvalidParameter,
            format!("{name:?} is not an action name (one key segment)"),
        ));
    }
    Ok(())
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
    /// A node key, or `<prefix>/**` for a subtree.
    Subscribe(SubId, String),
    /// A reactive list of a node's children (ADR 0025); `true`: each child's whole `~meta`.
    List(SubId, String, bool),
    /// Ends a subscription or a list.
    Unsubscribe(SubId),
    Set(ReqId, String, Value),
    Invoke(ReqId, String, String, Value),
    Log(Level, String),
}

/// What the runtime gives the buffer: reads and the network, which do not wait for the commit.
pub trait Services {
    fn now_us(&self) -> u64;
    fn store_get(&self, key: &str) -> Option<Vec<u8>>;
    /// Quota the link's store uses now ([`store_cost`] of each entry), without this event's
    /// pending writes.
    fn store_used(&self) -> u64;
    /// Keys in the link's store now, without this event's pending writes.
    fn store_keys(&self) -> usize;
    /// The value length of `key` in the store now; `None` when absent.
    fn store_len(&self, key: &str) -> Option<usize> {
        self.store_get(key).map(|v| v.len())
    }
    /// `Err` when this host gives the link no store (no data directory or no store key):
    /// `store_put` then fails with this error at once.
    fn store_ready(&self) -> Result<(), AppError> {
        Ok(())
    }
    /// The link holds at least `perm` on `key`.
    fn may(&self, key: &str, perm: Perm) -> bool;
    fn tcp_connect(&mut self, addr: &str, port: u16, timeout_ms: u32) -> Result<ConnId, AppError>;
    fn tcp_send(&mut self, c: ConnId, d: &[u8]) -> Result<(), AppError>;
    fn tcp_recv(&mut self, c: ConnId, max: u32, timeout_ms: u32) -> Result<Vec<u8>, AppError>;
    fn tcp_close(&mut self, c: ConnId);
    /// [`Host::tls_connect`]; a host without TLS refuses it.
    fn tls_connect(
        &mut self,
        host: &str,
        port: u16,
        timeout_ms: u32,
        ca_pem: Option<&str>,
    ) -> Result<ConnId, AppError> {
        let _ = (host, port, timeout_ms, ca_pem);
        Err(AppError::new(
            Status::NotSupported,
            "tls_connect: this host has no TLS",
        ))
    }
    /// Start TLS on an open plain connection (`SSLRequest` of PostgreSQL and MySQL), verifying
    /// the server's certificate for `host` as [`tls_connect`](Self::tls_connect) does; the
    /// connection keeps its id. On an error the connection is closed.
    fn tls_upgrade(
        &mut self,
        c: ConnId,
        host: &str,
        timeout_ms: u32,
        ca_pem: Option<&str>,
    ) -> Result<(), AppError> {
        let _ = (c, host, timeout_ms, ca_pem);
        Err(AppError::new(
            Status::NotSupported,
            "tls_upgrade: this host has no TLS",
        ))
    }
    /// The instance is gone: close every connection it opened.
    fn close_all(&mut self) {}
}

/// Bounds of one link (ADR 0023).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Limits {
    /// Nodes in the link's tree. The buffer cannot know which paths exist (a re-declare adds
    /// nothing), so the runtime enforces this one when it applies `DeclareNode`.
    pub max_nodes: usize,
    pub max_timers: usize,
    pub max_subs: usize,
    /// Lists at once ([`Host::list`]).
    pub max_lists: usize,
    pub max_inflight: usize,
    pub max_commands: usize,
    /// Quota of the store, counted in [`store_cost`].
    pub store_bytes: u64,
    pub max_store_keys: usize,
    /// Actions per node. Like `max_nodes`, the runtime enforces it (only it sees the tree).
    pub max_actions: usize,
}

impl Default for Limits {
    fn default() -> Self {
        Self {
            max_nodes: 10_000,
            max_timers: 1_000,
            max_subs: 1_000,
            max_lists: 2_000,
            max_inflight: 100,
            max_commands: 1_000,
            store_bytes: 1024 * 1024,
            max_store_keys: MAX_STORE_KEYS,
            max_actions: MAX_ACTIONS,
        }
    }
}

/// What the link holds now. The runtime owns these numbers and updates them between events.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct Counts {
    pub timers: usize,
    pub subs: usize,
    pub lists: usize,
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
    added_timers: HashSet<u64>,
    added_subs: HashSet<u64>,
    added_lists: HashSet<u64>,
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
            added_timers: HashSet::new(),
            added_subs: HashSet::new(),
            added_lists: HashSet::new(),
            added_inflight: 0,
            pending: HashMap::new(),
        }
    }

    /// Ends the event: returns its commands, or the error when the event went over a bound that
    /// the app could not see (a void call). Clears the per-event state either way.
    pub fn finish(&mut self) -> Result<Vec<Command>, AppError> {
        let cmds = std::mem::take(&mut self.cmds);
        let failed = self.failed.take();
        self.added_timers.clear();
        self.added_subs.clear();
        self.added_lists.clear();
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
        self.check_key_of(key, perm, false)
    }

    /// `other_sites`: another site's keys are read (`subscribe`, `list`) under an explicit
    /// grant (ADR 0025, D4); requests (`set`, `invoke`) stay on the link's own site.
    fn check_key_of(&self, key: &str, perm: Perm, other_sites: bool) -> Result<(), AppError> {
        let other = key
            .strip_prefix("wy/")
            .and_then(|r| r.split_once('/'))
            .filter(|_| other_sites && !key.starts_with(&self.site_prefix));
        let rest = match (key.strip_prefix(&self.site_prefix), other) {
            (Some(rest), _) => rest,
            (None, Some((_, rest))) if self.services.may(key, perm) => rest,
            _ => {
                return Err(AppError::new(
                    Status::PermissionDenied,
                    format!("{key} is outside {}", self.site_prefix),
                ))
            }
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

    /// Store quota and keys after this event's pending writes, with `pending[key]` replaced by
    /// `next` (`Some(len)` = a put of that length, `None` = a delete). An overwrite costs only the
    /// difference to the stored entry and is never a new key.
    fn store_after(&self, key: &str, next: Option<Option<usize>>) -> (u64, usize) {
        let mut used = self.services.store_used();
        let mut keys = self.services.store_keys();
        let mut account = |k: &str, put: Option<usize>| {
            let stored = self.services.store_len(k);
            if let Some(len) = stored {
                used = used.saturating_sub(store_cost(k.len(), len));
                keys = keys.saturating_sub(1);
            }
            if let Some(len) = put {
                used = used.saturating_add(store_cost(k.len(), len));
                keys += 1;
            }
        };
        for (k, v) in &self.pending {
            if next.is_some() && k == key {
                continue;
            }
            account(k, v.as_ref().map(Vec::len));
        }
        if let Some(put) = next {
            account(key, put);
        }
        (used, keys)
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
        // `max_nodes` is the runtime's: only it knows whether `path` is new.
        if let Some(actions) = &meta.actions {
            if actions.len() > self.limits.max_actions {
                self.fail(exhausted(&format!(
                    "{path:?}: at most {} actions per node",
                    self.limits.max_actions
                )));
                return;
            }
            if let Some(e) = actions.keys().find_map(|n| check_action_name(n).err()) {
                self.fail(e);
                return;
            }
        }
        self.push(Command::DeclareNode(path.to_owned(), meta));
    }

    fn declare_action(&mut self, path: &str, name: &str, action: ActionMeta) {
        if let Err(e) = check_action_name(name) {
            self.fail(e);
            return;
        }
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
        self.services.store_ready()?;
        if key.is_empty() || key.len() > MAX_STORE_KEY_LEN {
            return Err(exhausted(&format!(
                "a store key is 1 to {MAX_STORE_KEY_LEN} bytes"
            )));
        }
        let (used_now, keys_now) = self.store_after(key, None);
        let (used, keys) = self.store_after(key, Some(Some(value.len())));
        // a write that does not grow the store passes even over the quota (after a smaller
        // `store_mb`), so the app can shrink it; a quota of 0 refuses every write
        let quota = self.limits.store_bytes;
        if quota == 0 || (used > quota && used > used_now) {
            return Err(exhausted("store is full"));
        }
        if keys > self.limits.max_store_keys && keys > keys_now {
            return Err(exhausted(&format!(
                "too many store keys (at most {})",
                self.limits.max_store_keys
            )));
        }
        self.room()?;
        self.pending.insert(key.to_owned(), Some(value.to_vec()));
        self.cmds
            .push(Command::StorePut(key.to_owned(), value.to_vec()));
        Ok(())
    }

    fn store_delete(&mut self, key: &str) {
        // any key: a store written before the key bound may hold longer ones
        if self.room().is_ok() {
            self.pending.insert(key.to_owned(), None);
            self.cmds.push(Command::StoreDelete(key.to_owned()));
        }
    }

    fn subscribe(&mut self, key: &str) -> Result<SubId, AppError> {
        // one final `/**`: a subtree (ADR 0025); the prefix is checked as a node key
        self.check_key_of(key.strip_suffix("/**").unwrap_or(key), Perm::Read, true)?;
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
        self.added_lists.remove(&sub.0);
        self.push(Command::Unsubscribe(sub));
    }

    fn list(&mut self, key: &str, full: bool) -> Result<SubId, AppError> {
        self.check_key_of(key, Perm::Read, true)?;
        if self.counts.lists + self.added_lists.len() >= self.limits.max_lists {
            return Err(exhausted("too many lists"));
        }
        self.room()?;
        let id = self.id();
        self.added_lists.insert(id);
        self.cmds
            .push(Command::List(SubId(id), key.to_owned(), full));
        Ok(SubId(id))
    }

    fn set(&mut self, key: &str, value: Value) -> Result<ReqId, AppError> {
        let id = self.request(key, Perm::Write)?;
        self.cmds.push(Command::Set(id, key.to_owned(), value));
        Ok(id)
    }

    fn invoke(&mut self, key: &str, action: &str, args: Value) -> Result<ReqId, AppError> {
        check_action_name(action)?;
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

    fn tls_connect(
        &mut self,
        host: &str,
        port: u16,
        timeout_ms: u32,
        ca_pem: Option<&str>,
    ) -> Result<ConnId, AppError> {
        self.services.tls_connect(host, port, timeout_ms, ca_pem)
    }

    fn tls_upgrade(
        &mut self,
        c: ConnId,
        host: &str,
        timeout_ms: u32,
        ca_pem: Option<&str>,
    ) -> Result<(), AppError> {
        self.services.tls_upgrade(c, host, timeout_ms, ca_pem)
    }

    fn log(&mut self, level: Level, msg: &str) {
        self.push(Command::Log(level, msg.to_owned()));
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{AppError, ConnId, Host, Level};
    use wyrm_core::{ActionMeta, NodeMeta, Perm, Quality, Sample, Status, Value};

    struct FakeServices {
        used: u64,
        allow: bool,
        stored: HashMap<String, Vec<u8>>,
    }

    impl Services for FakeServices {
        fn now_us(&self) -> u64 {
            42
        }
        fn store_get(&self, key: &str) -> Option<Vec<u8>> {
            self.stored.get(key).cloned()
        }
        fn store_used(&self) -> u64 {
            self.used
                + self
                    .stored
                    .iter()
                    .map(|(k, v)| store_cost(k.len(), v.len()))
                    .sum::<u64>()
        }
        fn store_keys(&self) -> usize {
            self.stored.len()
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
            Box::new(FakeServices {
                used,
                allow,
                stored: HashMap::new(),
            }),
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
    fn store_put_without_a_store_is_refused() {
        struct NoStore(FakeServices);
        impl Services for NoStore {
            fn now_us(&self) -> u64 {
                self.0.now_us()
            }
            fn store_get(&self, k: &str) -> Option<Vec<u8>> {
                self.0.store_get(k)
            }
            fn store_used(&self) -> u64 {
                0
            }
            fn store_keys(&self) -> usize {
                0
            }
            fn store_ready(&self) -> Result<(), AppError> {
                Err(AppError::new(Status::NotSupported, "no store"))
            }
            fn may(&self, k: &str, p: Perm) -> bool {
                self.0.may(k, p)
            }
            fn tcp_connect(&mut self, a: &str, p: u16, t: u32) -> Result<ConnId, AppError> {
                self.0.tcp_connect(a, p, t)
            }
            fn tcp_send(&mut self, c: ConnId, d: &[u8]) -> Result<(), AppError> {
                self.0.tcp_send(c, d)
            }
            fn tcp_recv(&mut self, c: ConnId, m: u32, t: u32) -> Result<Vec<u8>, AppError> {
                self.0.tcp_recv(c, m, t)
            }
            fn tcp_close(&mut self, c: ConnId) {
                self.0.tcp_close(c)
            }
        }
        let mut h = BufferHost::new(
            Box::new(NoStore(FakeServices {
                used: 0,
                allow: true,
                stored: HashMap::new(),
            })),
            Limits::default(),
            Counts::default(),
            1,
            "wy/s".into(),
        );
        let e = h.store_put("a", &[1]).unwrap_err();
        assert_eq!(e.status, Status::NotSupported);
        assert!(h.finish().unwrap().is_empty());
    }

    #[test]
    fn store_put_replacing_a_key_counts_the_new_size_once() {
        let limits = Limits {
            store_bytes: STORE_BLOCK,
            ..Limits::default()
        };
        let mut h = host(0, true, limits);
        h.store_put("a", &[0; 8]).unwrap();
        h.store_put("a", &[0; 8]).unwrap();
        assert!(h.store_put("b", &[0; 8]).is_err());
    }

    fn stored_host(stored: &[(&str, usize)], limits: Limits) -> BufferHost {
        BufferHost::new(
            Box::new(FakeServices {
                used: 0,
                allow: true,
                stored: stored
                    .iter()
                    .map(|(k, n)| ((*k).to_owned(), vec![0; *n]))
                    .collect(),
            }),
            limits,
            Counts::default(),
            1,
            "wy/s".into(),
        )
    }

    #[test]
    fn each_store_entry_costs_at_least_one_block() {
        assert_eq!(store_cost(1, 0), STORE_BLOCK);
        assert_eq!(store_cost(1, 4095), STORE_BLOCK);
        assert_eq!(store_cost(1, 4096), 2 * STORE_BLOCK);
        let limits = Limits {
            store_bytes: 3 * STORE_BLOCK,
            ..Limits::default()
        };
        let mut h = host(0, true, limits);
        for k in ["a", "b", "c"] {
            h.store_put(k, &[1]).unwrap();
        }
        assert!(exhausted(&h.store_put("d", &[1]).unwrap_err()));
        // a delete in the same event makes room
        h.store_delete("a");
        h.store_put("d", &[1]).unwrap();
    }

    #[test]
    fn a_full_store_still_takes_overwrites_and_shrinks() {
        let limits = Limits {
            store_bytes: 2 * STORE_BLOCK,
            ..Limits::default()
        };
        // full: two one-block entries
        let mut h = stored_host(&[("a", 10), ("b", 10)], limits.clone());
        h.store_put("a", &[0; 100]).unwrap();
        assert!(exhausted(&h.store_put("c", &[1]).unwrap_err()));
        assert!(exhausted(&h.store_put("a", &[0; 5000]).unwrap_err()));
        h.finish().unwrap();
        // over the quota (it was made smaller): a write that does not grow passes
        let small = Limits {
            store_bytes: STORE_BLOCK,
            ..Limits::default()
        };
        let mut h = stored_host(&[("a", 10), ("b", 10)], small);
        h.store_put("a", &[1]).unwrap();
        assert!(exhausted(&h.store_put("c", &[1]).unwrap_err()));
        // but a quota of 0 (`store_mb: 0`) takes nothing
        let none = Limits {
            store_bytes: 0,
            ..Limits::default()
        };
        let mut h = stored_host(&[("a", 10)], none);
        assert!(exhausted(&h.store_put("a", &[1]).unwrap_err()));
    }

    #[test]
    fn store_keys_are_bounded_in_number_and_length() {
        let limits = Limits {
            max_store_keys: 2,
            ..Limits::default()
        };
        let mut h = stored_host(&[("a", 1)], limits);
        h.store_put("b", &[1]).unwrap();
        let e = h.store_put("c", &[1]).unwrap_err();
        assert!(exhausted(&e), "{e:?}");
        // an overwrite is not a new key
        h.store_put("a", &[2]).unwrap();
        h.store_put("b", &[2]).unwrap();
        h.store_delete("a");
        h.store_put("c", &[1]).unwrap();
        h.finish().unwrap();

        let mut h = host(0, true, Limits::default());
        h.store_put(&"k".repeat(MAX_STORE_KEY_LEN), &[1]).unwrap();
        for bad in [String::new(), "k".repeat(MAX_STORE_KEY_LEN + 1)] {
            assert!(exhausted(&h.store_put(&bad, &[1]).unwrap_err()));
        }
        assert_eq!(h.finish().unwrap().len(), 1);

        // a key longer than the bound, written before it: it can still be deleted
        let long = "k".repeat(MAX_STORE_KEY_LEN + 44);
        let mut h = stored_host(&[(long.as_str(), 1)], Limits::default());
        h.store_delete(&long);
        assert_eq!(h.store_get(&long), None);
        assert_eq!(h.finish().unwrap(), [Command::StoreDelete(long)]);
    }

    #[test]
    fn action_names_are_one_segment_and_bounded_per_node() {
        let mut h = host(0, true, Limits::default());
        for bad in ["*", "a/b", ".", "..", "", "$x", "~x", "a*"] {
            let e = h.invoke("wy/s/x", bad, Value::Null).unwrap_err();
            assert_eq!(e.status, Status::InvalidParameter, "{bad:?}");
            h.declare_action("", bad, ActionMeta::new());
            let e = h.finish().unwrap_err();
            assert_eq!(e.status, Status::InvalidParameter, "{bad:?}");
        }
        h.declare_action("", "go.now", ActionMeta::new());
        assert!(h.invoke("wy/s/x", "go-now", Value::Null).is_ok());
        assert_eq!(h.finish().unwrap().len(), 2);

        // inline actions of a node: the same names, at most `max_actions`
        let with = |names: Vec<String>| NodeMeta {
            actions: Some(names.into_iter().map(|n| (n, ActionMeta::new())).collect()),
            ..NodeMeta::default()
        };
        h.declare_node("p", with(vec!["a/b".into()]));
        assert_eq!(h.finish().unwrap_err().status, Status::InvalidParameter);
        let many = (0..=MAX_ACTIONS).map(|i| format!("a{i}")).collect();
        h.declare_node("p", with(many));
        assert!(exhausted(&h.finish().unwrap_err()));
        let enough = (0..MAX_ACTIONS).map(|i| format!("a{i}")).collect();
        h.declare_node("p", with(enough));
        assert_eq!(h.finish().unwrap().len(), 1);
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
                stored: HashMap::new(),
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
    fn re_declares_are_not_counted_by_the_buffer() {
        // The node bound belongs to the runtime: re-declaring existing nodes never fails here.
        let limits = Limits {
            max_nodes: 1,
            ..Limits::default()
        };
        let mut h = host(0, true, limits);
        for _ in 0..3 {
            h.declare_node("a", Default::default());
        }
        assert_eq!(h.finish().unwrap().len(), 3);
    }

    #[test]
    fn requests_check_grants_and_site() {
        let mut h = host(0, false, Limits::default());
        let e = h.set("wy/s/x", Value::Int(1)).unwrap_err();
        assert_eq!(e.status, Status::PermissionDenied);
        let mut h = host(0, true, Limits::default());
        let e = h.set("wy/other/x", Value::Int(1)).unwrap_err();
        assert_eq!(e.status, Status::PermissionDenied);
        // another site: read under a grant (here every key is granted), never written
        assert!(h.subscribe("wy/other/x").is_ok());
        assert!(h.list("wy/other/x", false).is_ok());
        assert_eq!(
            h.invoke("wy/other/x", "a", Value::Null).unwrap_err().status,
            Status::PermissionDenied
        );
        assert_eq!(h.finish().unwrap().len(), 2);
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
        assert_eq!(h.next_id(), 6);
    }

    #[test]
    fn request_keys_are_validated() {
        for prefix in ["wy/s", "wy/s/"] {
            let mut h = BufferHost::new(
                Box::new(FakeServices {
                    used: 0,
                    allow: true,
                    stored: HashMap::new(),
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
                "wy/s/a/**/p",
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

    #[test]
    fn a_subtree_subscription_and_lists() {
        let limits = Limits {
            max_lists: 1,
            ..Limits::default()
        };
        let mut h = host(0, true, limits);
        // `/**` only for subscribe, only at the end, on a node key
        assert!(h.subscribe("wy/s/downstream/plc/**").is_ok());
        for bad in ["wy/s/**/x", "wy/s/a/**/**", "wy/s/*/**"] {
            assert_eq!(
                h.subscribe(bad).unwrap_err().status,
                Status::InvalidParameter,
                "{bad}"
            );
        }
        assert_eq!(
            h.set("wy/s/downstream/plc/**", Value::Int(1))
                .unwrap_err()
                .status,
            Status::InvalidParameter
        );
        assert_eq!(
            h.list("wy/s/downstream/**", false).unwrap_err().status,
            Status::InvalidParameter
        );
        let mut no_grant = host(0, false, Limits::default());
        assert_eq!(
            no_grant.list("wy/x/downstream", false).unwrap_err().status,
            Status::PermissionDenied
        );
        let l = h.list("wy/s/downstream", false).unwrap();
        assert!(exhausted(&h.list("wy/s/downstream/plc", true).unwrap_err()));
        h.unsubscribe(l);
        assert!(h.list("wy/s/downstream/plc", true).is_ok());
        let cmds = h.finish().unwrap();
        assert!(matches!(&cmds[0], Command::Subscribe(_, k) if k == "wy/s/downstream/plc/**"));
        assert!(
            matches!(&cmds[1], Command::List(id, k, false) if *id == l && k == "wy/s/downstream")
        );
        assert!(matches!(&cmds[3], Command::List(_, k, true) if k == "wy/s/downstream/plc"));
        // the runtime's counts bound lists across events
        h.set_counts(Counts {
            lists: 1,
            ..Counts::default()
        });
        assert!(exhausted(&h.list("wy/s/downstream", false).unwrap_err()));
    }
}
