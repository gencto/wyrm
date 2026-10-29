//! Benchmarks of portable links (ADR 0023) on the reference app `examples/links/portable`
//! (`Echo`): `cargo bench -p wyrm-link-portable --bench roundtrip`.
//!
//! 1. **Event round trip, native vs WASM**: one `echo {value}` event into the engine and its
//!    command buffer, as the runtime's engine thread runs it. Native: `NativeEngine<Echo>`.
//!    WASM: the same crate built for wasm32 (`--features wasm`), made a component, called through
//!    `AppRunner` with the CBOR the WASM engine adds (arguments, `who`, the answer).
//! 2. **Restart after a trap**: `crash` (params `faults: true`) traps; then a new instance, its
//!    `start` and one `echo` answered. The runtime's backoff (1 s, ×2, cap 60 s) comes on top.
//! 3. **Memory per WASM instance**: the linear memory of one started instance, and the growth of
//!    the process's resident memory over [`INSTANCES`] started instances of one component.
//!
//! The link's Zenoh query (`TestHarness`, a router) is not in these numbers: it is the same for
//! every mode. Without the wasm32 target only the native numbers print.

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::{Duration, Instant};

use wyrm_core::{Perm, Status, Value};
use wyrm_example_portable::Echo;
use wyrm_link_api::buffer::{BufferHost, Counts, Limits, Services};
use wyrm_link_api::{AppError, ConnId, Who};
use wyrm_link_portable::{Engine, Event, NativeEngine};
use wyrm_wasm_host::{AppRunner, AppWorld, Host, Slot};

/// Round trips measured per engine (after [`WARMUP`]).
const ROUNDS: usize = 20_000;
const WARMUP: usize = 2_000;
/// Restarts measured per engine.
const RESTARTS: usize = 20;
/// Instances kept at once for the resident-memory figure.
const INSTANCES: usize = 50;

/// What the host gives the app between calls: a clock, no store content, no grants, no network.
struct Bare;

fn no_net() -> AppError {
    AppError::new(Status::NotSupported, "no network in the benchmark")
}

impl Services for Bare {
    fn now_us(&self) -> u64 {
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map_or(0, |d| d.as_micros() as u64)
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
    fn may(&self, _key: &str, _perm: Perm) -> bool {
        false
    }
    fn tcp_connect(&mut self, _a: &str, _p: u16, _t: u32) -> Result<ConnId, AppError> {
        Err(no_net())
    }
    fn tcp_send(&mut self, _c: ConnId, _d: &[u8]) -> Result<(), AppError> {
        Err(no_net())
    }
    fn tcp_recv(&mut self, _c: ConnId, _m: u32, _t: u32) -> Result<Vec<u8>, AppError> {
        Err(no_net())
    }
    fn tcp_close(&mut self, _c: ConnId) {}
}

fn buffer() -> BufferHost {
    BufferHost::new(
        Box::new(Bare),
        Limits::default(),
        Counts::default(),
        1,
        "wy/bench/downstream/echo".into(),
    )
}

fn params(faults: bool) -> Value {
    Value::Map(BTreeMap::from([("faults".to_owned(), Value::Bool(faults))]))
}

fn echo_args() -> Value {
    Value::Map(BTreeMap::from([("value".to_owned(), Value::UInt(7))]))
}

fn who() -> Who {
    Who {
        subject: Some("bench".into()),
        grants: vec![("wy/bench/downstream/echo/**".into(), Perm::Write)],
    }
}

fn cbor(v: &Value) -> Vec<u8> {
    wyrm_core::codec::to_vec(v).expect("encode")
}

// ---------- the two engines behind one call ----------

/// One engine of the benchmark: start an instance, answer `echo`, `crash`.
trait Bench {
    fn start(&mut self, host: &mut BufferHost, faults: bool);
    fn echo(&mut self, host: &mut BufferHost) -> Value;
    /// `true` when the instance is gone.
    fn crash(&mut self, host: &mut BufferHost) -> bool;
}

impl Bench for NativeEngine<Echo> {
    fn start(&mut self, host: &mut BufferHost, faults: bool) {
        Engine::start(self, host, &params(faults))
            .expect("no fault")
            .expect("started");
        host.finish().expect("start commands");
    }
    fn echo(&mut self, host: &mut BufferHost) -> Value {
        let ev = Event::Invoke {
            path: String::new(),
            action: "echo".into(),
            args: echo_args(),
            who: who(),
        };
        let v = self.event(host, ev).expect("no fault").expect("answer");
        host.finish().expect("commands");
        v.unwrap_or(Value::Null)
    }
    fn crash(&mut self, host: &mut BufferHost) -> bool {
        let ev = Event::Invoke {
            path: String::new(),
            action: "crash".into(),
            args: Value::Map(BTreeMap::new()),
            who: who(),
        };
        let gone = self.event(host, ev).is_err();
        let _ = host.finish();
        self.reset();
        gone
    }
}

/// The WASM engine's calls (`links/wasm` `WasmEngine`): CBOR in, CBOR out.
struct Wasm(AppRunner);

impl Bench for Wasm {
    fn start(&mut self, host: &mut BufferHost, faults: bool) {
        self.0
            .start(host, &cbor(&params(faults)))
            .expect("no trap")
            .expect("started");
        host.finish().expect("start commands");
    }
    fn echo(&mut self, host: &mut BufferHost) -> Value {
        let b = self
            .0
            .on_invoke(host, "", "echo", &cbor(&echo_args()), &who().to_cbor())
            .expect("no trap")
            .expect("answer");
        host.finish().expect("commands");
        wyrm_core::codec::from_slice(&b).expect("decode")
    }
    fn crash(&mut self, host: &mut BufferHost) -> bool {
        let gone = self
            .0
            .on_invoke(
                host,
                "",
                "crash",
                &cbor(&Value::Map(BTreeMap::new())),
                &who().to_cbor(),
            )
            .is_err();
        let _ = host.finish();
        gone && !self.0.is_live()
    }
}

// ---------- measurements ----------

struct Stats {
    p50: Duration,
    p99: Duration,
    mean: Duration,
}

fn stats(mut d: Vec<Duration>) -> Stats {
    d.sort();
    let at = |q: f64| d[((d.len() as f64 - 1.0) * q).round() as usize];
    let mean = d.iter().sum::<Duration>() / d.len() as u32;
    Stats {
        p50: at(0.5),
        p99: at(0.99),
        mean,
    }
}

fn us(d: Duration) -> String {
    format!("{:.2} µs", d.as_secs_f64() * 1e6)
}

fn round_trip(e: &mut dyn Bench) -> Stats {
    let mut host = buffer();
    e.start(&mut host, false);
    for _ in 0..WARMUP {
        assert_eq!(e.echo(&mut host), Value::UInt(7));
    }
    let mut d = Vec::with_capacity(ROUNDS);
    for _ in 0..ROUNDS {
        let t = Instant::now();
        let v = e.echo(&mut host);
        d.push(t.elapsed());
        assert_eq!(v, Value::UInt(7));
    }
    stats(d)
}

fn restart(e: &mut dyn Bench) -> Stats {
    let mut host = buffer();
    e.start(&mut host, true);
    let mut d = Vec::with_capacity(RESTARTS);
    for _ in 0..RESTARTS {
        assert!(e.crash(&mut host), "crash drops the instance");
        let t = Instant::now();
        e.start(&mut host, true);
        let v = e.echo(&mut host);
        d.push(t.elapsed());
        assert_eq!(v, Value::UInt(7));
    }
    stats(d)
}

/// Resident memory of this process in KiB (`ps`), if it can be read.
fn rss_kib() -> Option<u64> {
    let out = Command::new("ps")
        .args(["-o", "rss=", "-p", &std::process::id().to_string()])
        .output()
        .ok()?;
    String::from_utf8_lossy(&out.stdout).trim().parse().ok()
}

// ---------- the component ----------

fn wasm32_installed() -> bool {
    Command::new("rustc")
        .args([
            "--print",
            "target-libdir",
            "--target",
            "wasm32-unknown-unknown",
        ])
        .output()
        .ok()
        .filter(|o| o.status.success())
        .map(|o| PathBuf::from(String::from_utf8_lossy(&o.stdout).trim()))
        .is_some_and(|dir| dir.exists())
}

/// The example built as `wyr link pack` builds it, made a component.
fn component() -> Option<Vec<u8>> {
    if !wasm32_installed() {
        return None;
    }
    let repo = Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
    let target = repo.join("target/bench-example-portable");
    let out = Command::new(env!("CARGO"))
        .args(["build", "--release", "--lib", "-p", "wyrm-example-portable"])
        .args(["--target", "wasm32-unknown-unknown", "--features", "wasm"])
        .arg("--manifest-path")
        .arg(repo.join("Cargo.toml"))
        .arg("--target-dir")
        .arg(&target)
        .env_remove("RUSTFLAGS")
        .env_remove("CARGO_ENCODED_RUSTFLAGS")
        .output()
        .expect("run cargo");
    assert!(
        out.status.success(),
        "example build failed:\n{}",
        String::from_utf8_lossy(&out.stderr)
    );
    let core =
        std::fs::read(target.join("wasm32-unknown-unknown/release/wyrm_example_portable.wasm"))
            .expect("example wasm");
    Some(
        wit_component::ComponentEncoder::default()
            .module(&core)
            .expect("component type")
            .validate(true)
            .encode()
            .expect("componentize"),
    )
}

fn main() {
    // `cargo bench` passes `--bench`; a filter or `--list` from the harness is not ours
    if std::env::args().any(|a| a == "--list") {
        return;
    }
    // the native `crash` is a caught panic: keep its message out of the output
    std::panic::set_hook(Box::new(|_| {}));

    let native = round_trip(&mut NativeEngine::<Echo>::new());
    let native_restart = restart(&mut NativeEngine::<Echo>::new());

    let Some(bytes) = component() else {
        let _ = std::panic::take_hook();
        println!(
            "event round trip   native p50 {} p99 {} mean {}",
            us(native.p50),
            us(native.p99),
            us(native.mean)
        );
        println!("SKIP the WASM numbers: rustup target add wasm32-unknown-unknown");
        return;
    };
    let host = Host::new().expect("wasm host");
    let art = host.load::<AppWorld>(&bytes).expect("load component");
    let slot = Slot::new(art);
    let limits = wyrm_wasm_host::Limits::APP;
    let runner = || Wasm(AppRunner::new(slot.clone(), limits));

    let wasm = round_trip(&mut runner());
    let wasm_restart = restart(&mut runner());

    // memory: one instance, then many at once
    let before = rss_kib();
    let mut live = Vec::with_capacity(INSTANCES);
    let mut linear = 0;
    for _ in 0..INSTANCES {
        let mut w = runner();
        let mut h = buffer();
        w.start(&mut h, false);
        assert_eq!(w.echo(&mut h), Value::UInt(7));
        linear = w.0.memory_used().expect("live instance");
        live.push(w);
    }
    let after = rss_kib();
    let _ = std::panic::take_hook();

    println!("portable-echo, {ROUNDS} round trips, {RESTARTS} restarts (ADR 0023)");
    println!(
        "event round trip   native p50 {} p99 {} mean {}",
        us(native.p50),
        us(native.p99),
        us(native.mean)
    );
    println!(
        "event round trip   wasm   p50 {} p99 {} mean {}  (×{:.1} native p50)",
        us(wasm.p50),
        us(wasm.p99),
        us(wasm.mean),
        wasm.p50.as_secs_f64() / native.p50.as_secs_f64()
    );
    println!(
        "restart after trap wasm   p50 {} p99 {}  (native {}; the backoff of 1 s comes on top)",
        us(wasm_restart.p50),
        us(wasm_restart.p99),
        us(native_restart.p50)
    );
    let rss = match (before, after) {
        (Some(b), Some(a)) => format!(
            "{} KiB resident per instance over {INSTANCES}",
            a.saturating_sub(b) / INSTANCES as u64
        ),
        _ => "resident memory not readable".into(),
    };
    println!(
        "memory per wasm instance  {} KiB linear memory; {rss}",
        linear / 1024
    );
    drop(live);
}
