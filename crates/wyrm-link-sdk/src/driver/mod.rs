//! Driver framework (ADR 0004): `Connection → Device → Point` drivers on top
//! of the raw layer. A driver declares three typed parameter kinds and the
//! protocol I/O; [`Framework`] provides the tree, generated actions,
//! validate-then-diff edits, typed states with parent→child cascade, the
//! per-connection owner task, batched polling, read-back writes and the
//! quality ladder.

pub mod framework;
pub mod params;
pub mod persist;

pub use framework::{Framework, Tree};
pub use params::{ParamEnum, ParamSpec, Params};

use std::future::Future;
use std::time::Duration;
use wyrm_core::{NodeMeta, Value};

/// Point name within its device.
pub type PointId = String;

/// Outcome classes of driver I/O; they decide which node fails.
#[derive(Debug, Clone, PartialEq)]
pub enum DriverError {
    /// The connection is broken: close the transport and reconnect.
    Transport(String),
    /// The device does not answer (timeout); the connection is fine.
    Device(String),
    /// One point failed (protocol exception); the device answered.
    Point(String),
}

impl std::fmt::Display for DriverError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            DriverError::Transport(m) => write!(f, "transport: {m}"),
            DriverError::Device(m) => write!(f, "device: {m}"),
            DriverError::Point(m) => write!(f, "point: {m}"),
        }
    }
}

/// A protocol driver. All I/O methods run on the connection's owner task,
/// one at a time, each bounded by [`Driver::io_timeout`].
pub trait Driver: Sized + Send + Sync + 'static {
    const NAME: &'static str;
    const VERSION: &'static str;
    type Conn: Params;
    type Dev: Params;
    type Point: Params;
    /// The open connection (socket, serial port, session).
    type Transport: Send + 'static;
    /// A cached read plan for one `(device, poll period)` group.
    type Plan: Send + Sync + 'static;

    fn open(conn: &Self::Conn)
        -> impl Future<Output = Result<Self::Transport, DriverError>> + Send;

    /// Liveness probe of one device. `Device` error = no answer; a protocol
    /// exception means the device is alive and should be `Ok`.
    fn ping(
        t: &mut Self::Transport,
        dev: &Self::Dev,
    ) -> impl Future<Output = Result<(), DriverError>> + Send;

    /// Group `points` into reads. Cached until the group changes.
    fn plan(dev: &Self::Dev, points: &[(PointId, Self::Point)]) -> Self::Plan;

    fn poll(
        t: &mut Self::Transport,
        dev: &Self::Dev,
        plan: &Self::Plan,
    ) -> impl Future<Output = Vec<(PointId, Result<Value, DriverError>)>> + Send;

    /// Write `v` (already type-checked by the SDK). No optimistic update:
    /// the framework reads the point back afterwards.
    fn write(
        t: &mut Self::Transport,
        dev: &Self::Dev,
        id: &str,
        point: &Self::Point,
        v: &Value,
    ) -> impl Future<Output = Result<(), DriverError>> + Send;

    /// `type`, `unit`, `writable`, ranges of a point node.
    fn point_meta(point: &Self::Point) -> NodeMeta;

    fn poll_period(point: &Self::Point) -> Duration;

    /// `None` = no periodic device ping.
    fn ping_period(_dev: &Self::Dev) -> Option<Duration> {
        Some(Duration::from_secs(5))
    }

    fn io_timeout(_conn: &Self::Conn) -> Duration {
        Duration::from_secs(2)
    }

    /// Missed polls before `uncertain/stale` becomes `bad/comm_fail`.
    fn stale_misses() -> u32 {
        3
    }
}

/// Typed node state (ADR 0004), published in the branch's `status` leaf.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum NodeState {
    New,
    Connecting,
    Connected,
    Failed,
    Stopped,
    StoppedByParent,
}

impl NodeState {
    pub const NAMES: [&'static str; 6] = [
        "new",
        "connecting",
        "connected",
        "failed",
        "stopped",
        "stopped_by_parent",
    ];

    pub fn name(self) -> &'static str {
        Self::NAMES[self as usize]
    }
}

/// Reconnect delay: `1 s · 2^attempt`, capped at 60 s, scaled by
/// `1 + 0.2 · jitter` with `jitter ∈ [-1, 1]`.
pub fn backoff(attempt: u32, jitter: f64) -> Duration {
    let base = 2f64.powi(attempt.min(16) as i32).min(60.0);
    Duration::from_secs_f64(base * (1.0 + 0.2 * jitter.clamp(-1.0, 1.0)))
}

/// Cheap jitter in `[-1, 1]` (not for cryptography).
pub(crate) fn jitter() -> f64 {
    let nanos = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.subsec_nanos())
        .unwrap_or(0);
    let mut x = u64::from(nanos) ^ 0x9E37_79B9_7F4A_7C15;
    x ^= x << 13;
    x ^= x >> 7;
    x ^= x << 17;
    (x % 2001) as f64 / 1000.0 - 1.0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn backoff_grows_caps_and_jitters() {
        assert_eq!(backoff(0, 0.0), Duration::from_secs(1));
        assert_eq!(backoff(3, 0.0), Duration::from_secs(8));
        assert_eq!(backoff(10, 0.0), Duration::from_secs(60));
        assert_eq!(backoff(100, 0.0), Duration::from_secs(60));
        assert_eq!(backoff(10, 1.0), Duration::from_secs(72));
        assert_eq!(backoff(10, -1.0), Duration::from_secs(48));
        for _ in 0..100 {
            let j = jitter();
            assert!((-1.0..=1.0).contains(&j));
        }
    }

    #[test]
    fn state_names() {
        assert_eq!(NodeState::StoppedByParent.name(), "stopped_by_parent");
        assert_eq!(NodeState::Connected.name(), "connected");
    }
}
