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
//! - `wyrm:link/driver` (same file, ADR 0012): `point` plus the one import
//!   the host defines, `wyrm:link/tcp`, limited by the instance's
//!   [`NetPolicy`].
//! - `wyrm:app/app` (`wit/app/app.wit`, ADR 0023): a portable link. Its one
//!   import, `wyrm:app/host`, records the app's effects in a
//!   [`BufferHost`] that the caller lends the instance for each call
//!   ([`AppRunner`]). [`component_world`] tells the worlds apart by their
//!   exports.
//!
//! # Sandbox
//! - **No imports** but `wyrm:link/tcp` for the `driver` world and
//!   `wyrm:app/host` for the `app` world. The linker
//!   defines nothing else: no WASI, no files, no clocks, no random. A
//!   component that imports anything else is rejected at load with
//!   [`Error::Denied`] naming the import.
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
use std::collections::{HashMap, HashSet};
use std::io::{Read, Write};
use std::net::{IpAddr, SocketAddr, TcpStream};
use std::sync::{Arc, Mutex, RwLock};
use std::time::{Duration, Instant};
use wasmtime::component::{Component, Linker};
use wasmtime::{Config, Engine, ResourceLimiter, Store, Trap};
use wyrm_link_api::buffer::{BufferHost, Counts, Services};
use wyrm_link_api::{AppError, ConnId};

mod flow_world {
    wasmtime::component::bindgen!({ path: "wit/flow", world: "node" });
}

mod link_world {
    wasmtime::component::bindgen!({ path: "wit/link", world: "point" });
}

mod driver_world {
    wasmtime::component::bindgen!({ path: "wit/link", world: "driver" });
}

mod app_world {
    // A malformed CBOR argument traps the call: the import functions return `wasmtime::Result`.
    wasmtime::component::bindgen!({
        path: "wit/app",
        world: "app",
        imports: { default: trappable },
    });
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

    /// Default of a link driver call (`wyrm:link/driver`, ADR 0012): the
    /// time includes host network I/O.
    pub const LINK: Limits = Limits {
        fuel: 100_000_000,
        memory_bytes: 16 << 20,
        time: Duration::from_secs(2),
    };

    /// Upper bounds of a link driver call.
    pub const LINK_MAX: Limits = Limits {
        fuel: 1_000_000_000,
        memory_bytes: 64 << 20,
        time: Duration::from_secs(10),
    };

    /// Default of an `app` call (ADR 0023): 64 MiB, 2 s, host calls included.
    pub const APP: Limits = Limits::app(64, 2000);

    /// Upper bounds of an `app` call: 512 MiB, 10 s.
    pub const APP_MAX: Limits = Limits::app(512, 10_000);

    /// Fuel of an `app` call per millisecond of its time. Time is the bound an app is given;
    /// fuel only stops a guest that the epoch would stop too, so it is set well above what a
    /// call can burn in its time.
    pub const APP_FUEL_PER_MS: u64 = 1_000_000;

    /// The limits of an `app` call from the link's `memory_mb` and `call_ms` (clamped to
    /// 1..=512 MiB and 1..=10 000 ms).
    pub const fn app(memory_mb: u32, call_ms: u32) -> Limits {
        let mb = if memory_mb == 0 {
            1
        } else if memory_mb > 512 {
            512
        } else {
            memory_mb
        };
        let ms = if call_ms == 0 {
            1
        } else if call_ms > 10_000 {
            10_000
        } else {
            call_ms
        };
        Limits {
            fuel: Self::APP_FUEL_PER_MS * ms as u64,
            memory_bytes: (mb as usize) << 20,
            time: Duration::from_millis(ms as u64),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum Error {
    #[error("invalid component: {0}")]
    Invalid(String),
    #[error("import {0} denied: only wyrm:link/tcp for link drivers, wyrm:app/host for apps")]
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
    /// Linear memory of the instance now: the sum of its memories' sizes.
    memory_used: usize,
    net: Net,
    /// `app` world: the caller's buffer during a call, a placeholder between calls.
    app: Option<BufferHost>,
}

// ---------- network (ADR 0012) ----------

/// Open connections per instance.
pub const MAX_CONNS: usize = 4;
/// Largest `recv`.
pub const MAX_RECV: u32 = 64 << 10;
/// Largest `send`: a guest sends more in pieces, each within the call.
pub const MAX_SEND: usize = 64 << 10;

pub use wyrm_link_api::net::NetPolicy;

/// Network state of one instance: its policy, open connections and the
/// wall-clock end of the current call.
#[derive(Default)]
struct Net {
    policy: NetPolicy,
    conns: HashMap<u32, TcpStream>,
    next: u32,
    deadline: Option<Instant>,
}

impl Net {
    /// `ms` capped at the time left in the call; an error when none is left.
    fn budget(&self, ms: u32) -> Result<Duration, String> {
        let left = self
            .deadline
            .map(|d| d.saturating_duration_since(Instant::now()))
            .unwrap_or(Duration::ZERO);
        if left < Duration::from_millis(1) {
            return Err("no time left in this call".into());
        }
        Ok(Duration::from_millis(ms.max(1).into()).min(left))
    }

    fn conn(&mut self, h: u32) -> Result<&mut TcpStream, String> {
        self.conns
            .get_mut(&h)
            .ok_or_else(|| format!("no connection {h}"))
    }
}

impl driver_world::wyrm::link::tcp::Host for Ctx {
    fn connect(&mut self, addr: String, port: u16, timeout_ms: u32) -> Result<u32, String> {
        let ip: IpAddr = addr.parse().map_err(|_| format!("{addr}: an IP literal"))?;
        if !self.net.policy.allows(ip, port) {
            return Err(format!("{addr}:{port} is not in the link's net list"));
        }
        if self.net.conns.len() >= MAX_CONNS {
            return Err(format!("at most {MAX_CONNS} connections"));
        }
        let t = self.net.budget(timeout_ms)?;
        let s = TcpStream::connect_timeout(&SocketAddr::new(ip, port), t)
            .map_err(|e| format!("connect {addr}:{port}: {e}"))?;
        let _ = s.set_nodelay(true);
        self.net.next = self.net.next.wrapping_add(1);
        let h = self.net.next;
        self.net.conns.insert(h, s);
        Ok(h)
    }

    fn send(&mut self, conn: u32, data: Vec<u8>) -> Result<(), String> {
        if data.len() > MAX_SEND {
            return Err(format!("send: at most {MAX_SEND} bytes at a time"));
        }
        let mut off = 0;
        while off < data.len() {
            // the time left, again before every piece
            let t = self.net.budget(u32::MAX)?;
            let s = self.net.conn(conn)?;
            s.set_write_timeout(Some(t)).map_err(|e| e.to_string())?;
            match s.write(&data[off..]) {
                Ok(0) => return Err("send: connection closed".into()),
                Ok(n) => off += n,
                Err(e)
                    if matches!(
                        e.kind(),
                        std::io::ErrorKind::WouldBlock | std::io::ErrorKind::TimedOut
                    ) =>
                {
                    return Err("send: timeout".into())
                }
                Err(e) if e.kind() == std::io::ErrorKind::Interrupted => {}
                Err(e) => return Err(format!("send: {e}")),
            }
        }
        Ok(())
    }

    fn recv(&mut self, conn: u32, max: u32, timeout_ms: u32) -> Result<Vec<u8>, String> {
        let t = self.net.budget(timeout_ms)?;
        let s = self.net.conn(conn)?;
        s.set_read_timeout(Some(t)).map_err(|e| e.to_string())?;
        let mut buf = vec![0u8; max.min(MAX_RECV) as usize];
        match s.read(&mut buf) {
            Ok(n) => {
                buf.truncate(n);
                Ok(buf)
            }
            Err(e)
                if matches!(
                    e.kind(),
                    std::io::ErrorKind::WouldBlock | std::io::ErrorKind::TimedOut
                ) =>
            {
                Err("recv: timeout".into())
            }
            Err(e) => Err(format!("recv: {e}")),
        }
    }

    fn close(&mut self, conn: u32) {
        self.net.conns.remove(&conn);
    }
}

impl ResourceLimiter for Ctx {
    fn memory_growing(
        &mut self,
        current: usize,
        desired: usize,
        _maximum: Option<usize>,
    ) -> wasmtime::Result<bool> {
        // the limit is the instance's: all its memories together
        let used = self
            .memory_used
            .saturating_add(desired.saturating_sub(current));
        if used > self.memory_bytes {
            self.memory_hit = true;
            return Err(wasmtime::Error::msg(format!(
                "memory limit of {} bytes exceeded",
                self.memory_bytes
            )));
        }
        self.memory_used = used;
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

/// A WIT world the host can run: [`NodeWorld`], [`PointWorld`],
/// [`DriverWorld`] and [`AppWorld`].
pub trait World: sealed::Sealed + Sized + 'static {
    #[doc(hidden)]
    type Pre: Clone + Send + Sync;
    /// The one import this world may have (`wyrm:link/tcp` for `driver`).
    #[doc(hidden)]
    const IMPORT: Option<&'static str> = None;
    /// The linker with exactly the imports of this world.
    #[doc(hidden)]
    fn linker(engine: &Engine) -> wasmtime::Result<Linker<Ctx>> {
        Ok(Linker::new(engine))
    }
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

/// `wyrm:link/driver`: `point` plus `wyrm:link/tcp` (ADR 0012).
pub struct DriverWorld(driver_world::Driver);

impl sealed::Sealed for NodeWorld {}
impl sealed::Sealed for PointWorld {}
impl sealed::Sealed for DriverWorld {}
impl sealed::Sealed for AppWorld {}

impl World for DriverWorld {
    type Pre = driver_world::DriverPre<Ctx>;
    const IMPORT: Option<&'static str> = Some("wyrm:link/tcp@0.1.0");
    fn linker(engine: &Engine) -> wasmtime::Result<Linker<Ctx>> {
        let mut l = Linker::new(engine);
        driver_world::wyrm::link::tcp::add_to_linker::<Ctx, wasmtime::component::HasSelf<Ctx>>(
            &mut l,
            |c| c,
        )?;
        Ok(l)
    }
    fn pre(linker: &Linker<Ctx>, c: &Component) -> wasmtime::Result<Self::Pre> {
        driver_world::DriverPre::new(linker.instantiate_pre(c)?)
    }
    fn instantiate(pre: &Self::Pre, store: &mut Store<Ctx>) -> wasmtime::Result<Self> {
        pre.instantiate(store).map(DriverWorld)
    }
    fn init(&self, store: &mut Store<Ctx>, config: &[u8]) -> wasmtime::Result<Result<(), String>> {
        self.0.call_init(store, config)
    }
}

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
        if let Some((name, _)) = component
            .component_type()
            .imports(&self.engine)
            .find(|(name, _)| Some(*name) != W::IMPORT)
        {
            return Err(Error::Denied(name.to_owned()));
        }
        let linker = W::linker(&self.engine).map_err(|e| Error::Invalid(format!("{e:#}")))?;
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
pub type DriverArtifact = Artifact<DriverWorld>;
pub type AppArtifact = Artifact<AppWorld>;

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

    /// Grows by one with every [`Slot::swap`].
    pub fn generation(&self) -> u64 {
        self.0.read().unwrap_or_else(|p| p.into_inner()).0
    }

    fn current(&self) -> (u64, Artifact<W>) {
        let g = self.0.read().unwrap_or_else(|p| p.into_inner());
        (g.0, g.1.clone())
    }
}

// ---------- runner ----------

/// A fresh budget before a call: fuel, epoch deadline, the end of host I/O.
fn arm(store: &mut Store<Ctx>, limits: &Limits) -> Result<(), Error> {
    store.data_mut().memory_hit = false;
    // Host I/O timeouts end with the call (ADR 0012).
    store.data_mut().net.deadline = Some(Instant::now() + limits.time);
    store
        .set_fuel(limits.fuel)
        .map_err(|e| Error::Trap(format!("fuel: {e:#}")))?;
    store.set_epoch_deadline(limits.time.as_millis().div_ceil(TICK.as_millis()) as u64 + 1);
    Ok(())
}

/// Which limit a failed call ran into.
fn classify(limits: &Limits, e: wasmtime::Error, ctx: &Ctx) -> Error {
    if ctx.memory_hit {
        return Error::Memory(limits.memory_bytes);
    }
    match e.downcast_ref::<Trap>() {
        Some(Trap::OutOfFuel) => Error::Fuel(limits.fuel),
        Some(Trap::Interrupt) => Error::Time(limits.time),
        _ => Error::Trap(format!("{e:#}")),
    }
}

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
    net: NetPolicy,
    live: Option<Live<W>>,
    fuel_used: u64,
}

impl<W: World> Runner<W> {
    fn new(slot: Slot<W>, config: Vec<u8>, limits: Limits) -> Self {
        Self {
            slot,
            config,
            limits,
            net: NetPolicy::default(),
            live: None,
            fuel_used: 0,
        }
    }

    fn arm(store: &mut Store<Ctx>, limits: &Limits) -> Result<(), Error> {
        arm(store, limits)
    }

    fn classify(&self, e: wasmtime::Error, ctx: &Ctx) -> Error {
        classify(&self.limits, e, ctx)
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
                memory_used: 0,
                net: Net {
                    policy: self.net.clone(),
                    ..Net::default()
                },
                app: None,
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

/// A link point driver with network access (`wyrm:link/driver`, ADR 0012).
/// Host I/O blocks: run it on a thread of its own, not on an async worker.
pub struct LinkDriver(Runner<DriverWorld>);

impl LinkDriver {
    /// `limits.time` is the budget of one call, host I/O included.
    pub fn new(slot: Slot<DriverWorld>, config: Vec<u8>, limits: Limits, net: NetPolicy) -> Self {
        let mut r = Runner::new(slot, config, limits);
        r.net = net;
        Self(r)
    }

    pub fn start(&mut self) -> Result<(), Error> {
        self.0.ensure()
    }

    /// `read(point)` → the reading as canonical CBOR.
    pub fn read(&mut self, point: &[u8]) -> Result<Vec<u8>, Error> {
        self.0.call(|w, s| w.0.call_read(s, point))
    }

    pub fn write(&mut self, point: &[u8], value: &[u8]) -> Result<(), Error> {
        self.0.call(|w, s| w.0.call_write(s, point, value))
    }

    pub fn fuel_used(&self) -> u64 {
        self.0.fuel_used
    }
}

// ---------- world `wyrm:app/app` (ADR 0023) ----------

/// `wyrm:app/app`: a portable link. Its import `wyrm:app/host` delegates to the
/// [`BufferHost`] the caller lends the instance for a call.
pub struct AppWorld(app_world::App);

impl World for AppWorld {
    type Pre = app_world::AppPre<Ctx>;
    const IMPORT: Option<&'static str> = Some("wyrm:app/host@0.1.0");
    fn linker(engine: &Engine) -> wasmtime::Result<Linker<Ctx>> {
        let mut l = Linker::new(engine);
        app_world::wyrm::app::host::add_to_linker::<Ctx, wasmtime::component::HasSelf<Ctx>>(
            &mut l,
            |c| c,
        )?;
        Ok(l)
    }
    fn pre(linker: &Linker<Ctx>, c: &Component) -> wasmtime::Result<Self::Pre> {
        app_world::AppPre::new(linker.instantiate_pre(c)?)
    }
    fn instantiate(pre: &Self::Pre, store: &mut Store<Ctx>) -> wasmtime::Result<Self> {
        pre.instantiate(store).map(AppWorld)
    }
    /// Apps start through [`AppRunner::start`], with a buffer for their effects.
    fn init(
        &self,
        _store: &mut Store<Ctx>,
        _config: &[u8],
    ) -> wasmtime::Result<Result<(), String>> {
        Ok(Err("an app starts through AppRunner".into()))
    }
}

/// A malformed CBOR argument from the guest: the call traps.
fn decode<T>(what: &str, b: &[u8]) -> wasmtime::Result<T>
where
    T: for<'b> minicbor::Decode<'b, ()>,
{
    wyrm_core::codec::from_slice(b)
        .map_err(|e| wasmtime::Error::msg(format!("{what}: not the CBOR expected: {e}")))
}

impl Ctx {
    fn app(&mut self) -> wasmtime::Result<&mut BufferHost> {
        self.app
            .as_mut()
            .ok_or_else(|| wasmtime::Error::msg("wyrm:app/host outside an app call"))
    }
}

impl app_world::wyrm::app::host::Host for Ctx {
    fn declare_node(&mut self, path: String, meta: Vec<u8>) -> wasmtime::Result<()> {
        let meta = decode("declare-node meta", &meta)?;
        wyrm_link_api::Host::declare_node(self.app()?, &path, meta);
        Ok(())
    }

    fn declare_action(
        &mut self,
        path: String,
        name: String,
        action: Vec<u8>,
    ) -> wasmtime::Result<()> {
        let action = decode("declare-action meta", &action)?;
        wyrm_link_api::Host::declare_action(self.app()?, &path, &name, action);
        Ok(())
    }

    fn remove_node(&mut self, path: String) -> wasmtime::Result<()> {
        wyrm_link_api::Host::remove_node(self.app()?, &path);
        Ok(())
    }

    fn update(&mut self, path: String, sample: Vec<u8>) -> wasmtime::Result<()> {
        let sample = decode("update sample", &sample)?;
        wyrm_link_api::Host::update(self.app()?, &path, sample);
        Ok(())
    }

    fn now_us(&mut self) -> wasmtime::Result<u64> {
        Ok(wyrm_link_api::Host::now_us(self.app()?))
    }

    fn cancel_timer(&mut self, id: u64) -> wasmtime::Result<()> {
        wyrm_link_api::Host::cancel_timer(self.app()?, wyrm_link_api::TimerId(id));
        Ok(())
    }

    fn store_get(&mut self, key: String) -> wasmtime::Result<Option<Vec<u8>>> {
        Ok(wyrm_link_api::Host::store_get(self.app()?, &key))
    }

    fn set_timer(&mut self, after_ms: u64) -> wasmtime::Result<Result<u64, Vec<u8>>> {
        Ok(wyrm_link_api::Host::set_timer(self.app()?, after_ms)
            .map(|t| t.0)
            .map_err(|e| e.to_cbor()))
    }

    fn store_put(&mut self, key: String, value: Vec<u8>) -> wasmtime::Result<Result<(), Vec<u8>>> {
        Ok(wyrm_link_api::Host::store_put(self.app()?, &key, &value).map_err(|e| e.to_cbor()))
    }

    fn store_delete(&mut self, key: String) -> wasmtime::Result<()> {
        wyrm_link_api::Host::store_delete(self.app()?, &key);
        Ok(())
    }

    fn subscribe(&mut self, key: String) -> wasmtime::Result<Result<u64, Vec<u8>>> {
        Ok(wyrm_link_api::Host::subscribe(self.app()?, &key)
            .map(|s| s.0)
            .map_err(|e| e.to_cbor()))
    }

    fn unsubscribe(&mut self, id: u64) -> wasmtime::Result<()> {
        wyrm_link_api::Host::unsubscribe(self.app()?, wyrm_link_api::SubId(id));
        Ok(())
    }

    fn set(&mut self, key: String, value: Vec<u8>) -> wasmtime::Result<Result<u64, Vec<u8>>> {
        let value = decode("set value", &value)?;
        Ok(wyrm_link_api::Host::set(self.app()?, &key, value)
            .map(|r| r.0)
            .map_err(|e| e.to_cbor()))
    }

    fn invoke(
        &mut self,
        key: String,
        action: String,
        args: Vec<u8>,
    ) -> wasmtime::Result<Result<u64, Vec<u8>>> {
        let args = decode("invoke args", &args)?;
        Ok(
            wyrm_link_api::Host::invoke(self.app()?, &key, &action, args)
                .map(|r| r.0)
                .map_err(|e| e.to_cbor()),
        )
    }

    fn tcp_connect(
        &mut self,
        addr: String,
        port: u16,
        timeout_ms: u32,
    ) -> wasmtime::Result<Result<u32, Vec<u8>>> {
        Ok(
            wyrm_link_api::Host::tcp_connect(self.app()?, &addr, port, timeout_ms)
                .map(|c| c.0)
                .map_err(|e| e.to_cbor()),
        )
    }

    fn tcp_send(&mut self, conn: u32, data: Vec<u8>) -> wasmtime::Result<Result<(), Vec<u8>>> {
        Ok(
            wyrm_link_api::Host::tcp_send(self.app()?, ConnId(conn), &data)
                .map_err(|e| e.to_cbor()),
        )
    }

    fn tcp_recv(
        &mut self,
        conn: u32,
        max: u32,
        timeout_ms: u32,
    ) -> wasmtime::Result<Result<Vec<u8>, Vec<u8>>> {
        Ok(
            wyrm_link_api::Host::tcp_recv(self.app()?, ConnId(conn), max, timeout_ms)
                .map_err(|e| e.to_cbor()),
        )
    }

    fn tcp_close(&mut self, conn: u32) -> wasmtime::Result<()> {
        wyrm_link_api::Host::tcp_close(self.app()?, ConnId(conn));
        Ok(())
    }

    fn log(&mut self, level: u8, msg: String) -> wasmtime::Result<()> {
        wyrm_link_api::Host::log(self.app()?, wyrm_link_api::Level::from_code(level), &msg);
        Ok(())
    }
}

/// What a placeholder buffer serves: nothing. It only holds the place of the caller's buffer
/// in a store between calls.
struct NoServices;

impl Services for NoServices {
    fn now_us(&self) -> u64 {
        0
    }
    fn store_get(&self, _key: &str) -> Option<Vec<u8>> {
        None
    }
    fn store_used(&self) -> u64 {
        0
    }
    fn store_keys(&self) -> usize {
        0
    }
    fn store_ready(&self) -> Result<(), AppError> {
        Err(no_call())
    }
    fn may(&self, _key: &str, _perm: wyrm_core::Perm) -> bool {
        false
    }
    fn tcp_connect(&mut self, _a: &str, _p: u16, _t: u32) -> Result<ConnId, AppError> {
        Err(no_call())
    }
    fn tcp_send(&mut self, _c: ConnId, _d: &[u8]) -> Result<(), AppError> {
        Err(no_call())
    }
    fn tcp_recv(&mut self, _c: ConnId, _m: u32, _t: u32) -> Result<Vec<u8>, AppError> {
        Err(no_call())
    }
    fn tcp_close(&mut self, _c: ConnId) {}
}

fn no_call() -> AppError {
    AppError::new(wyrm_core::Status::InternalError, "no app call")
}

fn placeholder() -> BufferHost {
    BufferHost::new(
        Box::new(NoServices),
        wyrm_link_api::buffer::Limits::default(),
        Counts::default(),
        0,
        String::new(),
    )
}

/// One instance of an `app` component (ADR 0023). Each call takes the caller's
/// [`BufferHost`]: it lives in the store for the call (the imports record into it) and goes
/// back to the caller afterwards, on every path, a trap included. Host I/O blocks, so run it on
/// a thread of its own.
///
/// A call that returns an `Err` (trap, fuel, memory, time) drops the instance: a trapped
/// instance cannot be entered again. An app's own error is the inner `Err` and keeps it.
/// [`AppRunner::start`] makes a new instance from the slot's current artifact, which is how a
/// [`Slot::swap`] takes effect; [`AppRunner::replaced`] tells the caller that the slot moved on.
pub struct AppRunner {
    slot: Slot<AppWorld>,
    limits: Limits,
    live: Option<Live<AppWorld>>,
    live_sha: Option<String>,
    fuel_used: u64,
}

/// A call's result as the guest gives it: an app error is CBOR `{status, msg}`.
pub type AppResult<T> = Result<T, AppError>;

impl AppRunner {
    pub fn new(slot: Slot<AppWorld>, limits: Limits) -> Self {
        Self {
            slot,
            limits,
            live: None,
            live_sha: None,
            fuel_used: 0,
        }
    }

    pub fn slot(&self) -> &Slot<AppWorld> {
        &self.slot
    }

    /// An instance is alive.
    pub fn is_live(&self) -> bool {
        self.live.is_some()
    }

    /// The live instance runs another artifact than the slot holds now.
    pub fn replaced(&self) -> bool {
        self.live
            .as_ref()
            .is_some_and(|l| l.generation != self.slot.generation())
    }

    /// Drop the instance.
    pub fn reset(&mut self) {
        self.live = None;
    }

    /// Fuel the last call consumed.
    pub fn fuel_used(&self) -> u64 {
        self.fuel_used
    }

    /// Linear memory of the live instance in bytes (what its memories have grown to).
    pub fn memory_used(&self) -> Option<usize> {
        self.live.as_ref().map(|l| l.store.data().memory_used)
    }

    /// A new instance of the slot's current artifact, then its `start(config)`.
    pub fn start(&mut self, host: &mut BufferHost, config: &[u8]) -> Result<AppResult<()>, Error> {
        self.live = None;
        let (generation, art) = self.slot.current();
        let mut store = Store::new(
            &art.engine,
            Ctx {
                memory_bytes: self.limits.memory_bytes,
                memory_hit: false,
                memory_used: 0,
                net: Net::default(),
                app: Some(placeholder()),
            },
        );
        store.limiter(|c| c);
        arm(&mut store, &self.limits)?;
        let world = match AppWorld::instantiate(&art.pre, &mut store) {
            Ok(w) => w,
            Err(e) => return Err(classify(&self.limits, e, store.data())),
        };
        self.live = Some(Live {
            store,
            world,
            generation,
        });
        self.live_sha = Some(art.sha.clone());
        let r = self.call(host, |w, s| w.0.call_start(s, config))?;
        Ok(r.map_err(|e| AppError::from_cbor(&e)))
    }

    pub fn on_set(
        &mut self,
        host: &mut BufferHost,
        path: &str,
        value: &[u8],
        who: &[u8],
    ) -> Result<AppResult<()>, Error> {
        let r = self.call(host, |w, s| w.0.call_on_set(s, path, value, who))?;
        Ok(r.map_err(|e| AppError::from_cbor(&e)))
    }

    /// The answer is the CBOR of a `Value`.
    pub fn on_invoke(
        &mut self,
        host: &mut BufferHost,
        path: &str,
        action: &str,
        args: &[u8],
        who: &[u8],
    ) -> Result<AppResult<Vec<u8>>, Error> {
        let r = self.call(host, |w, s| w.0.call_on_invoke(s, path, action, args, who))?;
        Ok(r.map_err(|e| AppError::from_cbor(&e)))
    }

    pub fn on_timer(&mut self, host: &mut BufferHost, id: u64) -> Result<(), Error> {
        self.call(host, |w, s| w.0.call_on_timer(s, id))
    }

    pub fn on_value(
        &mut self,
        host: &mut BufferHost,
        sub: u64,
        key: &str,
        sample: &[u8],
    ) -> Result<(), Error> {
        self.call(host, |w, s| w.0.call_on_value(s, sub, key, sample))
    }

    /// `result`: the CBOR of the `Value` answered, or of the `AppError`.
    pub fn on_reply(
        &mut self,
        host: &mut BufferHost,
        req: u64,
        result: Result<&[u8], &[u8]>,
    ) -> Result<(), Error> {
        self.call(host, |w, s| w.0.call_on_reply(s, req, result))
    }

    /// `stop` runs at most [`AppRunner::STOP_TIME`] (or the call time, if shorter).
    pub fn stop(&mut self, host: &mut BufferHost) -> Result<(), Error> {
        let limits = self.limits;
        self.limits.time = limits.time.min(Self::STOP_TIME);
        let r = self.call(host, |w, s| w.0.call_stop(s));
        self.limits = limits;
        r
    }

    /// The bound of `stop` (ADR 0023: the old instance's `stop` before a hot start, 2 s).
    pub const STOP_TIME: Duration = Duration::from_secs(2);

    /// Hex SHA-256 of the artifact the live instance runs.
    pub fn live_sha256(&self) -> Option<&str> {
        self.live_sha.as_deref()
    }

    /// One call with the caller's buffer in the store. A failed call drops the instance.
    fn call<R>(
        &mut self,
        host: &mut BufferHost,
        f: impl FnOnce(&AppWorld, &mut Store<Ctx>) -> wasmtime::Result<R>,
    ) -> Result<R, Error> {
        let Some(live) = self.live.as_mut() else {
            return Err(Error::Trap("no instance".into()));
        };
        arm(&mut live.store, &self.limits)?;
        let Some(slot) = live.store.data_mut().app.as_mut() else {
            return Err(Error::Trap("no buffer in the store".into()));
        };
        std::mem::swap(host, slot);
        let r = f(&live.world, &mut live.store);
        // the caller's buffer comes back first, whatever happened
        if let Some(slot) = live.store.data_mut().app.as_mut() {
            std::mem::swap(host, slot);
        }
        self.fuel_used = self
            .limits
            .fuel
            .saturating_sub(live.store.get_fuel().unwrap_or(0));
        match r {
            Ok(v) => Ok(v),
            Err(e) => {
                let live = self.live.take().expect("live");
                Err(classify(&self.limits, e, live.store.data()))
            }
        }
    }
}

// ---------- telling worlds apart ----------

/// The world a component was built for, told by its exports and imports.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ComponentWorld {
    /// `wyrm:app/app` (ADR 0023).
    App,
    /// `wyrm:link/driver` (ADR 0012): `point` plus `wyrm:link/tcp`.
    Driver,
    /// `wyrm:link/point`.
    Point,
}

impl ComponentWorld {
    /// The name a package manifest gives the world (`world`, ADR 0023): `app`, `driver` or
    /// `point`.
    pub fn name(self) -> &'static str {
        match self {
            ComponentWorld::App => "app",
            ComponentWorld::Driver => "driver",
            ComponentWorld::Point => "point",
        }
    }
}

const APP_EXPORTS: [&str; 7] = [
    "start",
    "on-set",
    "on-invoke",
    "on-timer",
    "on-value",
    "on-reply",
    "stop",
];
const POINT_EXPORTS: [&str; 3] = ["init", "read", "write"];

/// Reads the component's top-level exports and imports (no compilation): an `app` exports
/// `start`, `on-set`, `on-invoke`, `on-timer`, `on-value`, `on-reply` and `stop`; a `point`
/// `init`, `read` and `write`; a `driver` is a `point` that imports `wyrm:link/tcp@0.1.0`.
/// Anything else is [`Error::Invalid`].
pub fn component_world(bytes: &[u8]) -> Result<ComponentWorld, Error> {
    use wasmparser::{Encoding, Parser, Payload};
    if bytes.len() > MAX_ARTIFACT_BYTES {
        return Err(Error::Invalid(format!(
            "{} bytes, at most {MAX_ARTIFACT_BYTES}",
            bytes.len()
        )));
    }
    let bad = |e: wasmparser::BinaryReaderError| Error::Invalid(e.to_string());
    let (mut exports, mut imports) = (HashSet::new(), HashSet::new());
    // nested modules and components come in the same stream, each between its own
    // `Version` and `End`
    let mut depth = 0usize;
    for payload in Parser::new(0).parse_all(bytes) {
        match payload.map_err(bad)? {
            Payload::Version { encoding, .. } => {
                if depth == 0 && encoding != Encoding::Component {
                    return Err(Error::Invalid("a core module, not a component".into()));
                }
                depth += 1;
            }
            Payload::End(_) => depth = depth.saturating_sub(1),
            Payload::ComponentExportSection(r) if depth == 1 => {
                for e in r {
                    exports.insert(e.map_err(bad)?.name.0.to_owned());
                }
            }
            Payload::ComponentImportSection(r) if depth == 1 => {
                for i in r {
                    imports.insert(i.map_err(bad)?.name.0.to_owned());
                }
            }
            _ => {}
        }
    }
    let has = |names: &[&str]| names.iter().all(|n| exports.contains(*n));
    if has(&APP_EXPORTS) {
        Ok(ComponentWorld::App)
    } else if has(&POINT_EXPORTS) {
        Ok(if imports.contains("wyrm:link/tcp@0.1.0") {
            ComponentWorld::Driver
        } else {
            ComponentWorld::Point
        })
    } else {
        Err(Error::Invalid(
            "neither an app (wyrm:app/app) nor a point driver (wyrm:link/point, driver)".into(),
        ))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// M2: the memory limit holds for the instance, all its memories together.
    #[test]
    fn the_memory_limit_is_the_sum_of_all_memories() {
        let mut c = Ctx {
            memory_bytes: 64 << 20,
            memory_hit: false,
            memory_used: 0,
            net: Net::default(),
            app: None,
        };
        // a first memory of 40 MiB, then a second one of 40 MiB: 80 MiB in all
        assert!(c.memory_growing(0, 40 << 20, None).unwrap());
        assert!(c.memory_growing(0, 40 << 20, None).is_err());
        assert!(c.memory_hit);
        // the first one grows to the limit; one byte more does not fit
        assert!(c.memory_growing(40 << 20, 64 << 20, None).unwrap());
        assert!(c.memory_growing(0, 1, None).is_err());
        assert_eq!(c.memory_used, 64 << 20);
    }
}
