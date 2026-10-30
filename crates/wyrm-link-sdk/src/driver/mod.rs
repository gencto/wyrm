//! Driver framework (ADR 0004): `Connection → Device → Point` drivers on top
//! of the raw layer. A driver declares three typed parameter kinds and the
//! protocol I/O; [`Framework`] provides the tree, generated actions,
//! validate-then-diff edits, typed states with parent→child cascade, the
//! per-connection owner task, batched polling, read-back writes, the
//! quality ladder, and (opt-in) driver actions, diagnostics counters and
//! folders between a device and its points.

mod diag;
pub mod framework;
pub mod params;
pub mod persist;

pub use framework::{Framework, Tree};
pub use params::{ParamEnum, ParamSpec, Params};

use crate::error::LinkError;
use std::future::Future;
use std::time::Duration;
use wyrm_core::{ActionMeta, NodeMeta, Value};

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

/// What became of one request on the wire, reported by a driver for the
/// diagnostics of its connection and device (ruling 12, [`Driver::take_outcomes`]).
/// `requests` counts every request; `exceptions`, `timeouts` and `errors`
/// are disjoint classes of the failed ones (so `requests` = answered +
/// exceptions + timeouts + errors). A retry is a request of its own.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Outcome {
    /// A normal reply after `rtt`.
    Reply(Duration),
    /// An exception reply after `rtt`: the device answered, the request failed.
    Exception(Duration),
    /// No reply within the request's timeout.
    Timeout,
    /// An I/O or protocol error (neither a timeout nor an exception).
    Error,
    /// A driver event counted in one of [`Driver::DIAG_EXTRA`] (not a request).
    Count(&'static str),
}

/// The level of a node that carries driver actions ([`Driver::actions`]).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Level {
    Connection,
    Device,
}

/// The node a driver action runs on ([`Driver::invoke`]).
pub enum Target<'a, D: Driver> {
    Connection,
    Device { id: &'a str, dev: &'a D::Dev },
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

    /// Bound on one ping (and on opening the connection).
    fn io_timeout(_conn: &Self::Conn) -> Duration {
        Duration::from_secs(2)
    }

    /// Bound on one poll of `plan`, which may take many requests (default:
    /// [`Driver::io_timeout`]). A poll cut by it is a device miss and its
    /// results are lost, so it should grow with the plan.
    fn poll_timeout(conn: &Self::Conn, _plan: &Self::Plan) -> Duration {
        Self::io_timeout(conn)
    }

    /// Bound on one write of `point` (default: [`Driver::io_timeout`]); a
    /// value written in several requests needs more.
    fn write_timeout(conn: &Self::Conn, _point: &Self::Point) -> Duration {
        Self::io_timeout(conn)
    }

    /// Read the point back after a failed write too (not after a broken
    /// connection), for a write that may have gone through in part.
    /// Default: only after a write that succeeded.
    fn read_back_on_error(_dev: &Self::Dev) -> bool {
        false
    }

    /// Heartbeat: publish an unchanged value again once its last sample is
    /// this old (on the next poll). `None` = publish on a change only.
    fn republish(_dev: &Self::Dev) -> Option<Duration> {
        None
    }

    /// Missed polls before `uncertain/stale` becomes `bad/comm_fail`.
    fn stale_misses() -> u32 {
        3
    }

    /// Values found on this host for a parameter (serial ports). The add
    /// and edit forms show them as the placeholder and in the description.
    fn choices(_param: &str) -> Vec<String> {
        Vec::new()
    }

    /// Name for people of the root action `rescan`, which looks for
    /// [`Driver::choices`] again and refreshes the forms (DSA: "Rescan For
    /// Serial Ports"). `None` = no such action.
    const RESCAN: Option<&'static str> = None;

    /// Driver actions of a connection or device node of `kind` (the node
    /// kind id, `""` on a single-kind level): `(name, meta)`. The meta sets
    /// the level (ADR 0004: reads `read`, value writes `write`, changes of
    /// the tree or config `config`; `config` when unset), the params and
    /// optionally `timeout_ms`, which bounds the call (default:
    /// [`Driver::io_timeout`], and never past the SDK's bound on the call,
    /// `LinkConfig::driver_timeout` without `timeout_ms`: set it for an
    /// action that may take longer). Names of framework actions and `add_*`
    /// are refused.
    fn actions(_level: Level, _kind: &str) -> Vec<(&'static str, ActionMeta)> {
        Vec::new()
    }

    /// Run a driver action on the connection's owner task, between polls
    /// (never during one). `args` passed the SDK's check against the
    /// declared params. An error with status `disconnected` means the
    /// transport broke: the framework reconnects.
    fn invoke(
        _t: &mut Self::Transport,
        _conn: &Self::Conn,
        _target: Target<'_, Self>,
        action: &str,
        _args: &Value,
    ) -> impl Future<Output = Result<Value, LinkError>> + Send {
        let e = LinkError::not_supported(format!("action {action}"));
        async move { Err(e) }
    }

    /// Diagnostics (ruling 12): connections and devices get the value
    /// leaves `requests`, `errors`, `timeouts`, `exceptions`, then
    /// [`Driver::DIAG_EXTRA`], then `last_rtt_ms` and `avg_rtt_ms`, fed by
    /// [`Driver::take_outcomes`]. Off by default.
    const DIAGNOSTICS: bool = false;

    /// Driver-specific counters (leaf names) beside the standard ones,
    /// counted by [`Outcome::Count`].
    const DIAG_EXTRA: &'static [&'static str] = &[];

    /// Folders (ruling 10): an organisational level between a device and its
    /// points, nested at most [`framework::MAX_FOLDER_DEPTH`] deep, with a
    /// name and nothing else (`add_folder`, `remove` with its contents; no
    /// rename). A point's key gains the folder path, its id stays unique on
    /// the device, so writes and plans do not see folders. Off by default; a
    /// driver that opts in may not have a device param named `folders`.
    const FOLDERS: bool = false;

    /// The outcomes of the requests sent since the last call (drained). The
    /// framework calls it after every ping, poll, write and action and
    /// counts them for that device and its connection.
    fn take_outcomes(_t: &mut Self::Transport) -> Vec<Outcome> {
        Vec::new()
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

    /// Values of the `status` enum leaf, by state (the DSA labels, plus
    /// `Connecting`); `~val.v` is the index.
    pub const LABELS: [&'static str; 6] = [
        "Unknown",
        "Connecting",
        "Connected",
        "Failed",
        "Stopped",
        "Stopped by Parent",
    ];

    pub fn name(self) -> &'static str {
        Self::NAMES[self as usize]
    }

    pub fn label(self) -> &'static str {
        Self::LABELS[self as usize]
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
