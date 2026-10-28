//! `app`: a portable link (ADR 0023) whose code is a WebAssembly component of world
//! `wyrm:app/app`, run by the same runtime as a native app ([`wyrm_link_portable::Runtime`]).
//!
//! The link param `component` names the `wasm` package; its component is
//! `<root>/<package>.wasm` (the same store as the `wasm` driver). `memory_mb` and `call_ms` are
//! the limits of one call (fuel follows the time, see [`Limits::app`]); the imports
//! (`wyrm:app/host`) record into the runtime's command buffer, so the app behaves as it does
//! natively. A trap, fuel, memory or time is a crash: the runtime restarts the instance after a
//! backoff, and the next `start` instantiates the slot's current artifact.
//!
//! [`reload_component`] swaps the component of every running link of a package (hot start):
//! the call in flight, if any, is cut off with `busy` and the new code starts at once with the
//! same store.

use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Mutex;

use wyrm_core::{Status, Value};
use wyrm_link_api::buffer::BufferHost;
use wyrm_link_api::AppError;
use wyrm_link_portable::{Engine, Event, Fault, MakeEngine, PortableConfig, Runtime};
use wyrm_link_sdk::{LinkCtx, LinkError};
use wyrm_wasm_host::{AppRunner, AppWorld, Error, Limits, Slot};

use crate::{component_path, host};

/// A portable link on a WASM component: driver `app`.
pub type App = Runtime<WasmEngine>;

/// The slots of the running `app` links in this process, by engine, with their package.
static SLOTS: Mutex<Vec<(u64, String, Slot<AppWorld>)>> = Mutex::new(Vec::new());
static NEXT: AtomicU64 = AtomicU64::new(1);

fn slots() -> std::sync::MutexGuard<'static, Vec<(u64, String, Slot<AppWorld>)>> {
    SLOTS.lock().unwrap_or_else(|p| p.into_inner())
}

/// Reads `<root>/<package>.wasm` again and swaps it into every running `app` link of the
/// package; returns how many. Each link cuts off its call in flight (`busy`) and starts the new
/// code with its store. Compiles the component: call it off the async workers.
pub fn reload_component(package: &str) -> Result<usize, LinkError> {
    let art = load(package)?;
    let mut n = 0;
    for (_, p, slot) in slots().iter() {
        if p == package {
            slot.swap(art.clone());
            n += 1;
        }
    }
    Ok(n)
}

fn load(package: &str) -> Result<wyrm_wasm_host::AppArtifact, LinkError> {
    let path = component_path(package).map_err(|e| LinkError::invalid_parameter(e.to_string()))?;
    let bytes = std::fs::read(&path)
        .map_err(|e| LinkError::internal(format!("component {package}: {e}")))?;
    host()
        .map_err(|e| LinkError::internal(e.to_string()))?
        .load::<AppWorld>(&bytes)
        .map_err(|e| LinkError::invalid_parameter(format!("component {package}: {e}")))
}

/// Runs the app of one link: one instance at a time, on the runtime's engine thread.
pub struct WasmEngine {
    id: u64,
    package: String,
    runner: AppRunner,
}

impl Drop for WasmEngine {
    fn drop(&mut self) {
        slots().retain(|(id, ..)| *id != self.id);
    }
}

fn crash(e: Error) -> Fault {
    Fault::Crash(e.to_string())
}

fn cbor(v: &impl minicbor::Encode<()>) -> Result<Vec<u8>, AppError> {
    wyrm_core::codec::to_vec(v).map_err(|e| AppError::new(Status::InternalError, e.to_string()))
}

impl Engine for WasmEngine {
    fn name(&self) -> String {
        self.package.clone()
    }

    fn version(&self) -> String {
        self.runner.slot().sha256()
    }

    fn start(
        &mut self,
        host: &mut BufferHost,
        config: &Value,
    ) -> Result<Result<(), AppError>, Fault> {
        let config = match cbor(config) {
            Ok(c) => c,
            Err(e) => return Ok(Err(e)),
        };
        self.runner.start(host, &config).map_err(crash)
    }

    fn event(
        &mut self,
        host: &mut BufferHost,
        ev: Event,
    ) -> Result<Result<Option<Value>, AppError>, Fault> {
        if !self.runner.is_live() {
            return Ok(Err(AppError::new(Status::Busy, "the link is not running")));
        }
        let stop = matches!(ev, Event::Stop);
        // a swapped slot: the old code takes no new event (but its `stop`)
        if !stop && self.runner.replaced() {
            return Err(Fault::Replaced);
        }
        let r = self.call(host, ev).map_err(crash)?;
        // swapped while the call ran: its result is not the new code's
        if !stop && self.runner.replaced() {
            return Err(Fault::Replaced);
        }
        Ok(r)
    }

    fn reset(&mut self) {
        self.runner.reset();
    }
}

impl WasmEngine {
    /// One event; the inner error is the app's.
    fn call(
        &mut self,
        host: &mut BufferHost,
        ev: Event,
    ) -> Result<Result<Option<Value>, AppError>, Error> {
        let r = &mut self.runner;
        Ok(match ev {
            Event::Set { path, value, who } => {
                let value = match cbor(&value) {
                    Ok(v) => v,
                    Err(e) => return Ok(Err(e)),
                };
                r.on_set(host, &path, &value, &who.to_cbor())?
                    .map(|()| None)
            }
            Event::Invoke {
                path,
                action,
                args,
                who,
            } => {
                let args = match cbor(&args) {
                    Ok(a) => a,
                    Err(e) => return Ok(Err(e)),
                };
                match r.on_invoke(host, &path, &action, &args, &who.to_cbor())? {
                    Ok(b) => wyrm_core::codec::from_slice::<Value>(&b)
                        .map(Some)
                        .map_err(|e| {
                            AppError::new(
                                Status::InvalidMessage,
                                format!("the app's answer is not CBOR: {e}"),
                            )
                        }),
                    Err(e) => Err(e),
                }
            }
            Event::Timer(t) => {
                r.on_timer(host, t.0)?;
                Ok(None)
            }
            Event::Value(sub, key, sample) => {
                // a sample always encodes; one that does not is not delivered
                if let Ok(s) = cbor(&sample) {
                    r.on_value(host, sub.0, &key, &s)?;
                }
                Ok(None)
            }
            Event::Reply(req, result) => {
                let bytes = match &result {
                    Ok(v) => cbor(v).map_err(|e| e.to_cbor()),
                    Err(e) => Err(e.to_cbor()),
                };
                r.on_reply(host, req.0, bytes.as_deref().map_err(|e| e.as_slice()))?;
                Ok(None)
            }
            Event::Stop => {
                r.stop(host)?;
                Ok(None)
            }
        })
    }
}

impl MakeEngine for WasmEngine {
    const NAME: &'static str = "app";
    const VERSION: &'static str = env!("CARGO_PKG_VERSION");
    type E = Self;

    fn make(cfg: &PortableConfig, _ctx: &LinkCtx) -> Result<Self, LinkError> {
        let package = cfg
            .component
            .clone()
            .ok_or_else(|| LinkError::invalid_parameter("params.component: the app's package"))?;
        let slot = Slot::new(load(&package)?);
        let id = NEXT.fetch_add(1, Ordering::Relaxed);
        slots().push((id, package.clone(), slot.clone()));
        Ok(Self {
            id,
            package,
            runner: AppRunner::new(slot, Limits::app(cfg.memory_mb, cfg.call_ms)),
        })
    }
}
