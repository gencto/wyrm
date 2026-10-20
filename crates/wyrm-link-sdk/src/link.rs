//! The driver contract. A driver does protocol I/O, declares nodes, publishes
//! values and handles `on_set`/`on_invoke`; everything else is the SDK.

use crate::auth::Caller;
use crate::ctx::LinkCtx;
use crate::error::{LinkError, Result};
use std::future::Future;
use tokio::sync::mpsc;
use wyrm_core::Value;

/// One connector driver. All methods run on a single task (`&mut self`), so
/// calls never overlap. Long-running work (streams, polling) belongs in tasks
/// the driver spawns itself.
///
/// The SDK checks `ptok`, `writable`/`invokable`, `cfg.min/max` and `enum`
/// before calling `on_set`/`on_invoke`, and applies `LinkConfig::driver_timeout`
/// (or `actions.*.timeout_ms`) to each call: a call that runs over is dropped
/// and the requester gets `timeout`.
pub trait Link: Send + Sized + 'static {
    /// Connector type name: `"modbus"`, `"mock"`. Goes to the root `~meta`.
    const NAME: &'static str;
    /// Driver semver. Goes to the root `~meta`.
    const VERSION: &'static str;
    type Config: Send + 'static;

    /// Connect to the device(s) and declare the subtree (profiles first, then
    /// nodes). The queryable is already up; liveliness is set after this
    /// returns `Ok`.
    fn start(cfg: Self::Config, ctx: LinkCtx) -> impl Future<Output = Result<Self>> + Send;

    /// Apply a new config without a restart. `Err` → the host restarts the link.
    fn reconfigure(&mut self, _cfg: Self::Config) -> impl Future<Output = Result<()>> + Send {
        async { Err(LinkError::not_supported("reconfigure")) }
    }

    /// Write `value` to the point at `path`. Already validated and authorized.
    fn on_set(
        &mut self,
        _path: &str,
        _value: Value,
        _who: &Caller,
    ) -> impl Future<Output = Result<()>> + Send {
        async { Err(LinkError::not_supported("set")) }
    }

    /// Run `action` on `path`. Reply through `out`: once for a plain action,
    /// any number of times then [`ReplySink::done`] for a stream. Returning
    /// without a reply answers `ok` with an empty payload.
    fn on_invoke(
        &mut self,
        _path: &str,
        _action: &str,
        _args: Value,
        _who: &Caller,
        _out: ReplySink,
    ) -> impl Future<Output = Result<()>> + Send {
        async { Err(LinkError::not_supported("invoke")) }
    }

    /// Graceful stop: close device connections. Bounded to 10 s by the SDK.
    fn stop(&mut self) -> impl Future<Output = ()> + Send {
        async {}
    }
}

#[derive(Debug)]
pub(crate) enum SinkItem {
    Value(Value),
    Done(Option<Value>),
    Error(LinkError),
}

/// Reply channel of one `invoke`. Cheap to clone and `Send + 'static`, so a
/// driver can move it into a task for streaming actions.
#[derive(Debug, Clone)]
pub struct ReplySink {
    tx: mpsc::Sender<SinkItem>,
}

impl ReplySink {
    pub(crate) fn new(capacity: usize) -> (Self, mpsc::Receiver<SinkItem>) {
        let (tx, rx) = mpsc::channel(capacity);
        (Self { tx }, rx)
    }

    /// Send one result (plain action) or one stream element. Waits when the
    /// requester is slow; `Err` when the request is gone (stop streaming).
    pub async fn reply(&self, v: impl Into<Value>) -> Result<()> {
        self.send(SinkItem::Value(v.into())).await
    }

    /// End a stream, optionally with a final element.
    pub async fn done(self, last: Option<Value>) -> Result<()> {
        self.send(SinkItem::Done(last)).await
    }

    /// End the request with an error status.
    pub async fn error(self, e: LinkError) -> Result<()> {
        self.send(SinkItem::Error(e)).await
    }

    /// `true` once the requester side is gone.
    pub fn is_closed(&self) -> bool {
        self.tx.is_closed()
    }

    async fn send(&self, item: SinkItem) -> Result<()> {
        self.tx
            .send(item)
            .await
            .map_err(|_| LinkError::new(wyrm_core::Status::Closed, "request closed"))
    }
}
