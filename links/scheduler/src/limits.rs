//! The link's bounds (ADR 0022, plan rulings 1 and 5), one place each, and [`Counted`]: the
//! host as the app sees it during one event, counting the commands the event buffers.

use wyrm_core::{ActionMeta, NodeMeta, Sample, Value};
use wyrm_link_api::{AppError, ConnId, Host, Level, ReqId, SubId, TimerId};

/// The shape caps of a schedule, validated by `wyrm-schedule` (ruling R1).
pub use wyrm_schedule::{HORIZON_DAYS, MAX_COUNT, MAX_EVENTS, MAX_INTERVAL};

/// The clock watchdog: the one host timer fires at least this often.
pub const WATCHDOG_MS: u64 = 30_000;
/// A difference larger than this between the wall clock and the time a timer was expected to
/// fire is a wall-clock step.
pub const CLOCK_STEP_MS: u64 = 2_000;
/// Commands one event buffers at most (the host fails an event over 1 000).
pub const COMMANDS_PER_EVENT: usize = 800;
/// Wall time one event spends on batched work at most (ruling R7); the rest goes on a `0` ms
/// timer, so a WASM call stays within its `call_ms`.
pub const EVENT_TIME_US: u64 = 500_000;
/// Commands kept free in every batch: re-arming the timer and a log line.
pub const RESERVE: usize = 4;
/// Nodes of the app (the host bounds 10 000; the root and its actions are outside it).
pub const NODE_BUDGET: usize = 9_500;
/// Nodes of one schedule without its events and targets: the schedule, `current`, `default`,
/// `enabled`, `events` and `targets`.
pub const NODES_PER_SCHEDULE: usize = 6;
/// Rows of one `get_events` at most, and without `limit`.
pub const MAX_ROWS: usize = 5_000;
pub const DEFAULT_ROWS: usize = 1_000;

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
    fn log(&mut self, level: Level, msg: &str) {
        self.one();
        self.host.log(level, msg)
    }
}
