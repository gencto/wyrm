//! WYRM WASM host (iteration 8): runs WebAssembly components on `wasmtime`
//! with hard limits and no ambient capabilities.
//!
//! # Worlds (WIT under `wit/`)
//! - `wyrm:flow/node` (`wit/flow/node.wit`): a flow node.
//!   `init(config) -> result`, `process(port, sample, state) ->
//!   result<tuple<emits, state>, string>`. Samples are the canonical CBOR
//!   `~val` payload `{0: v, 1: q, 2: t}`; `emits` is a CBOR array of
//!   `[port, sample]`. State is a blob owned by the host.
//! - `wyrm:link/point` (`wit/link/point.wit`): the read/write surface of a
//!   driver point. `init(config)`, `read(point) -> sample`,
//!   `write(point, value)`. All arguments are canonical CBOR.
//!
//! # Sandbox
//! - **No imports.** The linker defines nothing: no WASI, no files, no
//!   sockets, no clocks, no random. A component that imports anything is
//!   rejected at load with [`Error::Denied`] naming the import. Future
//!   capabilities (`~def.capabilities`) come only as explicit host imports.
//! - **Fuel** ([`Limits::fuel`]): the store gets a fresh budget before each
//!   call; exhaustion is [`Error::Fuel`].
//! - **Memory** ([`Limits::memory_bytes`]): a resource limiter turns any
//!   growth above the limit into a trap, [`Error::Memory`]. Instances,
//!   memories and tables per store are capped too.
//! - **Time** ([`Limits::time`]): epoch interruption with a 10 ms tick
//!   (one ticker thread per [`Host`]); [`Error::Time`].
//!
//! A trap poisons a component instance, so after any trap the host drops
//! the store and instantiates the component again (with `init`) on the next
//! call. Host-owned state makes this lossless for flow nodes.
//!
//! # Hot reload
//! An instance runs the artifact in its [`Slot`]. [`Slot::swap`] replaces the
//! artifact atomically; every runner on that slot re-instantiates on its
//! next call. No process restart, no lost state blob.

#![forbid(unsafe_code)]

use sha2::{Digest, Sha256};
use std::collections::HashMap;
use std::sync::{Arc, Mutex, RwLock};
use std::time::Duration;
use wasmtime::component::{Component, Linker};
use wasmtime::{Config, Engine, ResourceLimiter, Store, Trap};

mod flow_world {
    wasmtime::component::bindgen!({ path: "wit/flow", world: "node" });
}

mod link_world {
    wasmtime::component::bindgen!({ path: "wit/link", world: "point" });
}

/// Epoch tick of the time limit.
pub const TICK: Duration = Duration::from_millis(10);

/// Maximum size of a component binary the host compiles.
pub const MAX_ARTIFACT_BYTES: usize = 16 << 20;

/// Per-call limits of one instance.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Limits {
    /// Fuel per call (roughly one unit per wasm instruction).
    pub fuel: u64,
    /// Linear memory per instance, bytes.
    pub memory_bytes: usize,
    /// Wall time per call (granularity [`TICK`]).
    pub time: Duration,
}

impl Default for Limits {
    fn default() -> Self {
        Self {
            fuel: 10_000_000,
            memory_bytes: 16 << 20,
            time: Duration::from_millis(100),
        }
    }
}

impl Limits {
    /// Upper bounds a configuration may ask for.
    pub const MAX: Limits = Limits {
        fuel: 1_000_000_000,
        memory_bytes: 256 << 20,
        time: Duration::from_secs(1),
    };
}

#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum Error {
    #[error("invalid component: {0}")]
    Invalid(String),
    #[error("import {0} denied: components get no host imports")]
    Denied(String),
    #[error("fuel limit of {0} exhausted")]
    Fuel(u64),
    #[error("memory limit of {0} bytes exceeded")]
    Memory(usize),
    #[error("time limit of {0:?} exceeded")]
    Time(Duration),
    #[error("trap: {0}")]
    Trap(String),
    /// The guest returned `err(msg)`.
    #[error("{0}")]
    Guest(String),
}

/// Lowercase hex SHA-256 of `bytes`: the artifact id.
pub fn sha256_hex(bytes: &[u8]) -> String {
    Sha256::digest(bytes)
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect()
}

/// `true` for 64 lowercase hex characters.
pub fn is_sha256_hex(s: &str) -> bool {
    s.len() == 64 && s.bytes().all(|b| matches!(b, b'0'..=b'9' | b'a'..=b'f'))
}

// ---------- store data and limiter ----------

#[doc(hidden)]
pub struct Ctx {
    memory_bytes: usize,
    memory_hit: bool,
}

impl ResourceLimiter for Ctx {
    fn memory_growing(
        &mut self,
        _current: usize,
        desired: usize,
        _maximum: Option<usize>,
    ) -> wasmtime::Result<bool> {
        if desired > self.memory_bytes {
            self.memory_hit = true;
            return Err(wasmtime::Error::msg(format!(
                "memory limit of {} bytes exceeded",
                self.memory_bytes
            )));
        }
        Ok(true)
    }

    fn table_growing(
        &mut self,
        _current: usize,
        desired: usize,
        _maximum: Option<usize>,
    ) -> wasmtime::Result<bool> {
        Ok(desired <= 10_000)
    }

    fn instances(&self) -> usize {
        16
    }

    fn tables(&self) -> usize {
        16
    }

    fn memories(&self) -> usize {
        4
    }
}

// ---------- worlds ----------

mod sealed {
    pub trait Sealed {}
}

/// A WIT world the host can run. Implemented for [`NodeWorld`] and
/// [`PointWorld`] only.
pub trait World: sealed::Sealed + Sized + 'static {
    #[doc(hidden)]
    type Pre: Clone + Send + Sync;
    #[doc(hidden)]
    fn pre(linker: &Linker<Ctx>, c: &Component) -> wasmtime::Result<Self::Pre>;
    #[doc(hidden)]
    fn instantiate(pre: &Self::Pre, store: &mut Store<Ctx>) -> wasmtime::Result<Self>;
    #[doc(hidden)]
    fn init(&self, store: &mut Store<Ctx>, config: &[u8]) -> wasmtime::Result<Result<(), String>>;
}

/// `wyrm:flow/node`.
pub struct NodeWorld(flow_world::Node);

/// `wyrm:link/point`.
pub struct PointWorld(link_world::Point);

impl sealed::Sealed for NodeWorld {}
impl sealed::Sealed for PointWorld {}

impl World for NodeWorld {
    type Pre = flow_world::NodePre<Ctx>;
    fn pre(linker: &Linker<Ctx>, c: &Component) -> wasmtime::Result<Self::Pre> {
        flow_world::NodePre::new(linker.instantiate_pre(c)?)
    }
    fn instantiate(pre: &Self::Pre, store: &mut Store<Ctx>) -> wasmtime::Result<Self> {
        pre.instantiate(store).map(NodeWorld)
    }
    fn init(&self, store: &mut Store<Ctx>, config: &[u8]) -> wasmtime::Result<Result<(), String>> {
        self.0.call_init(store, config)
    }
}

impl World for PointWorld {
    type Pre = link_world::PointPre<Ctx>;
    fn pre(linker: &Linker<Ctx>, c: &Component) -> wasmtime::Result<Self::Pre> {
        link_world::PointPre::new(linker.instantiate_pre(c)?)
    }
    fn instantiate(pre: &Self::Pre, store: &mut Store<Ctx>) -> wasmtime::Result<Self> {
        pre.instantiate(store).map(PointWorld)
    }
    fn init(&self, store: &mut Store<Ctx>, config: &[u8]) -> wasmtime::Result<Result<(), String>> {
        self.0.call_init(store, config)
    }
}

// ---------- host and artifacts ----------

/// One `wasmtime` engine (fuel and epoch interruption on), a cache of
/// compiled components by SHA-256, and the epoch ticker thread. Cheap to
/// clone; the ticker stops when the last clone is dropped.
#[derive(Clone)]
pub struct Host {
    engine: Engine,
    compiled: Arc<Mutex<HashMap<String, Component>>>,
}

impl Host {
    pub fn new() -> Result<Self, Error> {
        let mut cfg = Config::new();
        cfg.consume_fuel(true)
            .epoch_interruption(true)
            .wasm_component_model(true);
        let engine = Engine::new(&cfg).map_err(|e| Error::Invalid(format!("engine: {e:#}")))?;
        let weak = engine.weak();
        std::thread::Builder::new()
            .name("wyrm-wasm-epoch".into())
            .spawn(move || loop {
                std::thread::sleep(TICK);
                match weak.upgrade() {
                    Some(e) => e.increment_epoch(),
                    None => return,
                }
            })
            .map_err(|e| Error::Invalid(format!("epoch ticker: {e}")))?;
        Ok(Self {
            engine,
            compiled: Arc::new(Mutex::new(HashMap::new())),
        })
    }

    /// Compile (or take from the cache), reject any import, check the
    /// exports against world `W`.
    pub fn load<W: World>(&self, bytes: &[u8]) -> Result<Artifact<W>, Error> {
        if bytes.len() > MAX_ARTIFACT_BYTES {
            return Err(Error::Invalid(format!(
                "{} bytes, at most {MAX_ARTIFACT_BYTES}",
                bytes.len()
            )));
        }
        let sha = sha256_hex(bytes);
        let cached = self.cache().get(&sha).cloned();
        let component = match &cached {
            Some(c) => c.clone(),
            None => {
                Component::new(&self.engine, bytes).map_err(|e| Error::Invalid(format!("{e:#}")))?
            }
        };
        if let Some((name, _)) = component.component_type().imports(&self.engine).next() {
            return Err(Error::Denied(name.to_owned()));
        }
        let linker = Linker::<Ctx>::new(&self.engine);
        let pre = W::pre(&linker, &component).map_err(|e| Error::Invalid(format!("{e:#}")))?;
        // Only components that passed every check stay compiled.
        if cached.is_none() {
            self.cache().insert(sha.clone(), component);
        }
        Ok(Artifact {
            sha,
            pre,
            engine: self.engine.clone(),
        })
    }

    /// Drop a compiled component from the cache.
    pub fn forget(&self, sha: &str) {
        self.cache().remove(sha);
    }

    fn cache(&self) -> std::sync::MutexGuard<'_, HashMap<String, Component>> {
        self.compiled.lock().unwrap_or_else(|p| p.into_inner())
    }
}

/// A compiled component checked against world `W`.
pub struct Artifact<W: World> {
    sha: String,
    pre: W::Pre,
    engine: Engine,
}

impl<W: World> Clone for Artifact<W> {
    fn clone(&self) -> Self {
        Self {
            sha: self.sha.clone(),
            pre: self.pre.clone(),
            engine: self.engine.clone(),
        }
    }
}

impl<W: World> Artifact<W> {
    /// Hex SHA-256 of the component binary.
    pub fn sha256(&self) -> &str {
        &self.sha
    }
}

pub type NodeArtifact = Artifact<NodeWorld>;
pub type PointArtifact = Artifact<PointWorld>;

/// The artifact runners use; [`Slot::swap`] is the hot reload.
pub struct Slot<W: World>(Arc<RwLock<(u64, Artifact<W>)>>);

impl<W: World> Clone for Slot<W> {
    fn clone(&self) -> Self {
        Self(self.0.clone())
    }
}

impl<W: World> Slot<W> {
    pub fn new(a: Artifact<W>) -> Self {
        Self(Arc::new(RwLock::new((0, a))))
    }

    /// Replace the artifact; runners switch on their next call. Returns the
    /// previous one.
    pub fn swap(&self, a: Artifact<W>) -> Artifact<W> {
        let mut g = self.0.write().unwrap_or_else(|p| p.into_inner());
        g.0 += 1;
        std::mem::replace(&mut g.1, a)
    }

    pub fn sha256(&self) -> String {
        self.current().1.sha
    }

    fn current(&self) -> (u64, Artifact<W>) {
        let g = self.0.read().unwrap_or_else(|p| p.into_inner());
        (g.0, g.1.clone())
    }
}

// ---------- runner ----------

struct Live<W> {
    store: Store<Ctx>,
    world: W,
    generation: u64,
}

/// One instance of a component with limits, re-instantiated after a trap
/// or a slot swap.
struct Runner<W: World> {
    slot: Slot<W>,
    config: Vec<u8>,
    limits: Limits,
    live: Option<Live<W>>,
    fuel_used: u64,
}

impl<W: World> Runner<W> {
    fn new(slot: Slot<W>, config: Vec<u8>, limits: Limits) -> Self {
        Self {
            slot,
            config,
            limits,
            live: None,
            fuel_used: 0,
        }
    }

    fn arm(store: &mut Store<Ctx>, limits: &Limits) -> Result<(), Error> {
        store.data_mut().memory_hit = false;
        store
            .set_fuel(limits.fuel)
            .map_err(|e| Error::Trap(format!("fuel: {e:#}")))?;
        store.set_epoch_deadline(limits.time.as_millis().div_ceil(TICK.as_millis()) as u64 + 1);
        Ok(())
    }

    fn classify(&self, e: wasmtime::Error, ctx: &Ctx) -> Error {
        if ctx.memory_hit {
            return Error::Memory(self.limits.memory_bytes);
        }
        match e.downcast_ref::<Trap>() {
            Some(Trap::OutOfFuel) => Error::Fuel(self.limits.fuel),
            Some(Trap::Interrupt) => Error::Time(self.limits.time),
            _ => Error::Trap(format!("{e:#}")),
        }
    }

    /// Instantiate (with `init`) if there is no live instance or the slot
    /// changed.
    fn ensure(&mut self) -> Result<(), Error> {
        let (generation, art) = self.slot.current();
        if self
            .live
            .as_ref()
            .is_some_and(|l| l.generation == generation)
        {
            return Ok(());
        }
        self.live = None;
        let mut store = Store::new(
            &art.engine,
            Ctx {
                memory_bytes: self.limits.memory_bytes,
                memory_hit: false,
            },
        );
        store.limiter(|c| c);
        Self::arm(&mut store, &self.limits)?;
        let world = match W::instantiate(&art.pre, &mut store) {
            Ok(w) => w,
            Err(e) => return Err(self.classify(e, store.data())),
        };
        Self::arm(&mut store, &self.limits)?;
        match world.init(&mut store, &self.config) {
            Ok(Ok(())) => {}
            Ok(Err(m)) => return Err(Error::Guest(format!("init: {m}"))),
            Err(e) => return Err(self.classify(e, store.data())),
        }
        self.live = Some(Live {
            store,
            world,
            generation,
        });
        Ok(())
    }

    fn call<R>(
        &mut self,
        f: impl FnOnce(&W, &mut Store<Ctx>) -> wasmtime::Result<Result<R, String>>,
    ) -> Result<R, Error> {
        self.ensure()?;
        let live = self.live.as_mut().expect("ensured");
        Self::arm(&mut live.store, &self.limits)?;
        let r = f(&live.world, &mut live.store);
        self.fuel_used = self
            .limits
            .fuel
            .saturating_sub(live.store.get_fuel().unwrap_or(0));
        match r {
            Ok(Ok(v)) => Ok(v),
            Ok(Err(m)) => Err(Error::Guest(m)),
            Err(e) => {
                // A trapped instance cannot be entered again.
                let live = self.live.take().expect("live");
                Err(self.classify(e, live.store.data()))
            }
        }
    }
}

/// A flow node instance (`wyrm:flow/node`).
pub struct FlowNode(Runner<NodeWorld>);

impl FlowNode {
    /// `config`: the node's config value as canonical CBOR.
    pub fn new(slot: Slot<NodeWorld>, config: Vec<u8>, limits: Limits) -> Self {
        Self(Runner::new(slot, config, limits))
    }

    /// Instantiate and `init` now (deploy-time check); otherwise the first
    /// call does it.
    pub fn start(&mut self) -> Result<(), Error> {
        self.0.ensure()
    }

    /// `process(port, sample, state)` → `(emits, new_state)`.
    pub fn process(
        &mut self,
        port: &str,
        sample: &[u8],
        state: &[u8],
    ) -> Result<(Vec<u8>, Vec<u8>), Error> {
        self.0.call(|w, s| w.0.call_process(s, port, sample, state))
    }

    /// Fuel the last call consumed.
    pub fn fuel_used(&self) -> u64 {
        self.0.fuel_used
    }

    pub fn slot(&self) -> &Slot<NodeWorld> {
        &self.0.slot
    }
}

/// A point driver instance (`wyrm:link/point`).
pub struct PointDriver(Runner<PointWorld>);

impl PointDriver {
    pub fn new(slot: Slot<PointWorld>, config: Vec<u8>, limits: Limits) -> Self {
        Self(Runner::new(slot, config, limits))
    }

    pub fn start(&mut self) -> Result<(), Error> {
        self.0.ensure()
    }

    /// `read(point)` → the `~val` payload as canonical CBOR.
    pub fn read(&mut self, point: &[u8]) -> Result<Vec<u8>, Error> {
        self.0.call(|w, s| w.0.call_read(s, point))
    }

    pub fn write(&mut self, point: &[u8], value: &[u8]) -> Result<(), Error> {
        self.0.call(|w, s| w.0.call_write(s, point, value))
    }

    pub fn fuel_used(&self) -> u64 {
        self.0.fuel_used
    }

    pub fn slot(&self) -> &Slot<PointWorld> {
        &self.0.slot
    }
}
