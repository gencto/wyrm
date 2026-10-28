//! What the runtime asks of an engine: run one call of an app at a time on the engine thread.

use wyrm_core::{Sample, Value};
use wyrm_link_api::buffer::BufferHost;
use wyrm_link_api::{AppError, ReqId, SubId, TimerId, Who};
use wyrm_link_sdk::{LinkCtx, LinkError};

use crate::PortableConfig;

/// One call into the app.
#[derive(Debug, Clone, PartialEq)]
pub enum Event {
    Set {
        path: String,
        value: Value,
        who: Who,
    },
    Invoke {
        path: String,
        action: String,
        args: Value,
        who: Who,
    },
    Timer(TimerId),
    /// Subscription, node key (without `~val`), sample.
    Value(SubId, String, Sample),
    Reply(ReqId, Result<Value, AppError>),
    Stop,
}

/// The call did not complete as the app's own.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Fault {
    /// The instance is gone: a panic, a trap, fuel, memory or time ran out. The runtime drops the
    /// instance, keeps the store and starts again after a backoff.
    Crash(String),
    /// The engine's code was replaced (a hot swap) before or during the call. The runtime drops
    /// the call's effects and answers its caller `busy`; the hot start follows (see
    /// [`Engine::code_changes`]).
    Replaced,
}

impl std::fmt::Display for Fault {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Fault::Crash(m) => f.write_str(m),
            Fault::Replaced => f.write_str("the link's code was replaced"),
        }
    }
}

/// Runs an app: the native engine calls Rust code, the WASM engine a component. All calls run on
/// one OS thread owned by the runtime; effects go into the [`BufferHost`].
pub trait Engine: Send + 'static {
    fn name(&self) -> String;
    fn version(&self) -> String;
    /// Make a new instance and call its `start`. The outer `Err` is a fault; the inner one the app's.
    fn start(
        &mut self,
        host: &mut BufferHost,
        config: &Value,
    ) -> Result<Result<(), AppError>, Fault>;
    /// One event. `Set` gives `Ok(None)`, `Invoke` `Ok(Some(result))`; other events `Ok(None)`.
    fn event(
        &mut self,
        host: &mut BufferHost,
        ev: Event,
    ) -> Result<Result<Option<Value>, AppError>, Fault>;
    /// Drop the instance (before a restart).
    fn reset(&mut self);
    /// Announces a new generation of the engine's code (a hot swap). The runtime then runs the
    /// old instance's `stop`, starts the new code at once on the same store, and answers calls
    /// cut off by the swap with `busy`. `None`: the code never changes (native).
    fn code_changes(&self) -> Option<tokio::sync::watch::Receiver<u64>> {
        None
    }
}

/// Makes the engine of a link. The runtime is generic over the engine type, and a `trait Link`
/// needs its `NAME` and `VERSION` at compile time, so they live here: the native engine takes them
/// from its `App`; the WASM engine (`links/wasm`) names its driver.
pub trait MakeEngine {
    /// The driver name on the link root (`Link::NAME`).
    const NAME: &'static str;
    /// The driver version on the link root (`Link::VERSION`).
    const VERSION: &'static str;
    type E: Engine;
    fn make(cfg: &PortableConfig, ctx: &LinkCtx) -> Result<Self::E, LinkError>;
}
