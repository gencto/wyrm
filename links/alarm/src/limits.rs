//! The link's bounds (ADR 0034 "Model", "Store"), one place each, and [`Counted`]: the host as
//! the app sees it during one event, counting the commands the event buffers (as the scheduler's,
//! ADR 0022 ruling 5).

use wyrm_core::{ActionMeta, NodeMeta, Sample, Value};
use wyrm_link_api::{AppError, ConnId, Host, Level, ReqId, SubId, TimerId};

/// The clock watchdog: the one host timer fires at least this often.
pub const WATCHDOG_MS: u64 = 30_000;
/// A difference larger than this between the wall clock and the time a timer was expected to
/// fire is a wall-clock step.
pub const CLOCK_STEP_MS: u64 = 2_000;
/// Commands one event buffers at most (the host fails an event over 1 000).
pub const COMMANDS_PER_EVENT: usize = 800;
/// Wall time one event spends on batched work at most; the rest goes on a `0` ms timer, so a
/// WASM call stays within its `call_ms`.
pub const EVENT_TIME_US: u64 = 500_000;
/// Commands kept free in every batch: re-arming the timer and a log line.
pub const RESERVE: usize = 4;
/// Nodes of the app (the host bounds 10 000; the root and its actions are outside it).
pub const NODE_BUDGET: usize = 9_500;
/// Nodes of one class without its watches: the folder, `open`, `active`, `unacked`, `alarms`,
/// `watches`.
pub const NODES_PER_CLASS: usize = 6;
/// Nodes of `stats/`: the folder and its values ([`STAT_NAMES`]).
pub const STATS_NODES: usize = 1 + STAT_NAMES.len();
/// The counters under `stats/`.
pub const STAT_NAMES: [&str; 7] = [
    "open", "active", "unacked", "records", "watches", "raised", "dropped",
];
pub const MAX_CLASSES: usize = 200;
pub const MAX_WATCHES_PER_CLASS: usize = 500;
/// Watches in all: one subscription each (the host bounds 1 000 subscriptions).
pub const MAX_WATCHES: usize = 1_000;
/// Keys a subtree watch (`<prefix>/**`) keeps state for; over it the watch shows `error`.
pub const MAX_KEYS_PER_WATCH: usize = 2_000;
/// Open records at most: over it the oldest record that is normal but unacknowledged is
/// acknowledged by `system:overflow`.
pub const MAX_OPEN: usize = 10_000;
pub const MAX_SINKS: usize = 16;
/// Records per store page `p/<n>` and journal entries per `j/<n>`.
pub const PAGE: u64 = 64;
pub const JOURNAL_PAGE: u64 = 256;
/// Journal pages kept at most (102 400 entries); older ones go, confirmed or not.
pub const MAX_JOURNAL_PAGES: u64 = 400;
pub const MAX_NOTES: usize = 20;
pub const MAX_NOTE_LEN: usize = 1_024;
pub const MAX_MESSAGE_LEN: usize = 1_024;
/// Text of a record's `value` at most (longer text is cut).
pub const MAX_VALUE_TEXT: usize = 256;
/// Rows of one `get_alarms` at most, and without `limit`.
pub const MAX_ROWS: usize = 5_000;
pub const DEFAULT_ROWS: usize = 500;
/// Pages one `get_alarms` reads at most (16 384 records); `complete: false` beyond.
pub const MAX_PAGES_PER_QUERY: usize = 256;
/// Rows of a class's `alarms` table value at most.
pub const TABLE_ROWS: usize = 200;
/// A changed table, the counts and the stats are published at most this often.
pub const PUBLISH_MS: u64 = 500;
/// Rows of one sink batch: by default and at most; bytes of the values at most.
pub const DEFAULT_BATCH_ROWS: usize = 1_000;
pub const MAX_BATCH_ROWS: usize = 5_000;
pub const MAX_BATCH_BYTES: usize = 1 << 20;
/// Params `retention_days` and `max_records`: defaults and caps.
pub const DEFAULT_RETENTION_DAYS: u64 = 365;
pub const MAX_RETENTION_DAYS: u64 = 3_650;
pub const DEFAULT_MAX_RECORDS: u64 = 100_000;
pub const MAX_MAX_RECORDS: u64 = 1_000_000;
/// Pages one purge run deletes at most; the run comes again daily (and with `purge`).
pub const PURGE_PAGES_PER_RUN: usize = 100;
pub const PURGE_INTERVAL_MS: u64 = 86_400_000;
/// Inhibits, staleness and escalations at most (seconds).
pub const MAX_INHIBIT_S: u64 = 86_400;
pub const MAX_STALE_S: u64 = 30 * 86_400;
pub const MAX_ESCALATION_S: u64 = 30 * 86_400;

/// The host during one event, counting what the event buffers. Every call that buffers a
/// command counts one, failed ones too (a bound is never passed by an undercount).
pub struct Counted<'a> {
    host: &'a mut dyn Host,
    used: usize,
    began_us: u64,
}

impl<'a> Counted<'a> {
    pub fn new(host: &'a mut dyn Host) -> Self {
        let began_us = host.now_us();
        Counted {
            host,
            used: 0,
            began_us,
        }
    }

    /// Room for `n` more commands, the [`RESERVE`] kept, within the event's time.
    pub fn room(&self, n: usize) -> bool {
        self.used + n + RESERVE <= COMMANDS_PER_EVENT
            && self.host.now_us().saturating_sub(self.began_us) < EVENT_TIME_US
    }

    fn one(&mut self) {
        self.used += 1;
    }
}

impl Host for Counted<'_> {
    fn declare_node(&mut self, path: &str, meta: NodeMeta) {
        self.one();
        self.host.declare_node(path, meta)
    }
    fn declare_action(&mut self, path: &str, name: &str, action: ActionMeta) {
        self.one();
        self.host.declare_action(path, name, action)
    }
    fn remove_node(&mut self, path: &str) {
        self.one();
        self.host.remove_node(path)
    }
    fn update(&mut self, path: &str, sample: Sample) {
        self.one();
        self.host.update(path, sample)
    }
    fn now_us(&self) -> u64 {
        self.host.now_us()
    }
    fn set_timer(&mut self, after_ms: u64) -> Result<TimerId, AppError> {
        self.one();
        self.host.set_timer(after_ms)
    }
    fn cancel_timer(&mut self, t: TimerId) {
        self.one();
        self.host.cancel_timer(t)
    }
    fn store_get(&self, key: &str) -> Option<Vec<u8>> {
        self.host.store_get(key)
    }
    fn store_put(&mut self, key: &str, value: &[u8]) -> Result<(), AppError> {
        self.one();
        self.host.store_put(key, value)
    }
    fn store_delete(&mut self, key: &str) {
        self.one();
        self.host.store_delete(key)
    }
    fn subscribe(&mut self, key: &str) -> Result<SubId, AppError> {
        self.one();
        self.host.subscribe(key)
    }
    fn unsubscribe(&mut self, sub: SubId) {
        self.one();
        self.host.unsubscribe(sub)
    }
    fn list(&mut self, key: &str, full: bool) -> Result<SubId, AppError> {
        self.one();
        self.host.list(key, full)
    }
    fn set(&mut self, key: &str, value: Value) -> Result<ReqId, AppError> {
        self.one();
        self.host.set(key, value)
    }
    fn invoke(&mut self, key: &str, action: &str, args: Value) -> Result<ReqId, AppError> {
        self.one();
        self.host.invoke(key, action, args)
    }
    fn tcp_connect(&mut self, addr: &str, port: u16, timeout_ms: u32) -> Result<ConnId, AppError> {
        self.host.tcp_connect(addr, port, timeout_ms)
    }
    fn tcp_send(&mut self, c: ConnId, data: &[u8]) -> Result<(), AppError> {
        self.host.tcp_send(c, data)
    }
    fn tcp_recv(&mut self, c: ConnId, max: u32, timeout_ms: u32) -> Result<Vec<u8>, AppError> {
        self.host.tcp_recv(c, max, timeout_ms)
    }
    fn tcp_close(&mut self, c: ConnId) {
        self.host.tcp_close(c)
    }
    fn tls_connect(
        &mut self,
        host: &str,
        port: u16,
        timeout_ms: u32,
        ca_pem: Option<&str>,
    ) -> Result<ConnId, AppError> {
        self.host.tls_connect(host, port, timeout_ms, ca_pem)
    }
    fn tls_upgrade(
        &mut self,
        c: ConnId,
        host: &str,
        timeout_ms: u32,
        ca_pem: Option<&str>,
    ) -> Result<(), AppError> {
        self.host.tls_upgrade(c, host, timeout_ms, ca_pem)
    }
    fn random_bytes(&mut self, n: u32) -> Result<Vec<u8>, AppError> {
        self.host.random_bytes(n)
    }
    fn log(&mut self, level: Level, msg: &str) {
        self.one();
        self.host.log(level, msg)
    }
}
