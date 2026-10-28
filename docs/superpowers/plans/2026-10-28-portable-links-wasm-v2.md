# Portable links and WASM world v2 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One link source (`App`) that runs embedded in `wyrmd`, as a process package and as a WASM component (world `wyrm:app/app`), with the full link API, capabilities granted at install, and fault isolation with restart.

**Architecture:** `wyrm-link-api` holds the `App`/`Host` traits, a command buffer (`BufferHost`) and the CBOR boundary types; every host runs the app through the same buffer, so effects and errors are identical. `wyrm-link-portable` holds the host runtime (`Runtime<E: Engine>`, an SDK `Link`) that applies commands to `LinkCtx`, runs timers, subscriptions, requests, the store and restarts; `NativeEngine<A>` calls an `App` in-process, `WasmEngine` (in `links/wasm`) calls a component. `wyrm-link-guest` implements `Host` over the WIT imports for apps built to `wasm32-unknown-unknown`; `wyr link pack` builds and componentizes them.

**Tech Stack:** Rust stable, tokio, wasmtime `=40.0.4` (component model), `wit-bindgen =0.57.1` (guest), `wit-component =0.243.0` (in `wyr`), minicbor via `wyrm-core`, ring (sealing), zenoh via `wyrm-client`.

**Spec:** `docs/adr/0023-portable-links-and-wasm-world-v2.md` (accepted). Related: ADR 0004, 0010, 0011, 0012, 0013, 0021.

## Global Constraints

- WIT package `wyrm:app@0.1.0`, world `app`; `wyrm:link@0.1.0` (`point`, `driver`, `tcp`) unchanged byte for byte.
- No WASI anywhere; the linker defines only `wyrm:app/host` for `app` components.
- All boundary data canonical CBOR through `wyrm-core` (principle 5); errors on the boundary are CBOR `{status: uint (wire code), msg: tstr}`.
- Defaults/limits: call time 2000 ms (max 10000), memory 64 MiB (max 512), store 1 MiB (max 64 MiB); at most 10 000 nodes, 1 000 timers, 1 000 subscriptions, 100 requests in flight, 1 000 commands per event.
- Restart backoff 1 s, ×2, cap 60 s, ±20 % jitter; re-declare window 10 s; `stuck` after 30 s without a completed event (native only).
- App paths may not start with `.`; the link root node `""` belongs to the host.
- `wyrm-core` and `wyrm-link-api` must build for `wasm32-unknown-unknown` (CI step).
- Repo conventions: `cargo fmt`, `cargo +1.99.0 clippy --workspace --all-targets --all-features -- -D warnings`, `cargo test --workspace`; wire enums via `wire_enum!`, no `as u8` (CONTRIBUTING.md); commit straight to `main` after each green task, `Co-Authored-By` line.

## Review Focus

1. An app that panics or traps inside `start` (not only in later events) — must back off and retry, not spin; test in Task 4 (`panic_in_start_backs_off`).
2. A `store_put` that would exceed `store_mb` — the `Host` call returns `resource_exhausted`, nothing partial is written; test in Task 2 (`store_put_over_quota_is_refused`) and Task 4 (`store_survives_restart_and_quota_holds`).
3. A request (`set`/`subscribe`) to a key outside the link's grants, and to a key in another site — refused with `permission_denied` before any query leaves; test in Task 4 (`requests_outside_grants_are_refused`).
4. A hot swap while a `set` is in flight — the caller gets `busy`, the new instance starts with the old store; test in Task 6 (`hot_swap_keeps_store_and_fails_inflight`).
5. A component that is a `driver`/`point` world uploaded where an `app` is expected (and the reverse) — install picks the world from exports and never mislabels; test in Task 7 (`install_picks_world_from_exports`).

---

### Task 1: `wyrm-link-api` crate — traits, ids, errors, `NetPolicy`, wasm32 build

**Files:**
- Create: `crates/wyrm-link-api/Cargo.toml`, `crates/wyrm-link-api/src/lib.rs` (traits, ids, `AppError`, `Who`, `Level`), `crates/wyrm-link-api/src/net.rs` (moved `NetPolicy`)
- Modify: `Cargo.toml` (workspace member + `wyrm-link-api` dependency), `crates/wyrm-wasm-host/src/lib.rs` (`pub use wyrm_link_api::net::NetPolicy;`, remove its own copy), `crates/wyrm-wasm-host/Cargo.toml`, `rust-toolchain.toml` (`targets = ["wasm32-unknown-unknown"]`), `.github/workflows/ci.yml` (step `cargo build -p wyrm-core -p wyrm-link-api --target wasm32-unknown-unknown`)
- Test: `crates/wyrm-link-api/src/lib.rs` (unit), existing `crates/wyrm-wasm-host` tests

**Interfaces:**
- Produces:
  - `pub struct TimerId(pub u64); pub struct SubId(pub u64); pub struct ReqId(pub u64); pub struct ConnId(pub u32);` (Copy, Eq, Hash, Debug)
  - `pub struct AppError { pub status: wyrm_core::Status, pub msg: String }` with `AppError::new(Status, impl Into<String>)`, `to_cbor(&self) -> Vec<u8>`, `from_cbor(&[u8]) -> AppError` (unreadable → `internal_error`)
  - `pub struct Who { pub subject: Option<String>, pub grants: Vec<(String, wyrm_core::Perm)> }` with `to_cbor`/`from_cbor`, `Who::may(&self, key_suffix: &str, Perm) -> bool` (longest-prefix grant, as `Grants::perm`)
  - `pub enum Level { Error, Warn, Info, Debug }` with `code(self) -> u8` (0–3) and `from_code(u8) -> Level` (unknown → `Info`); it is not a `tables.json` code table, so `wire_enum!` does not apply
  - `pub trait App` and `pub trait Host` exactly as in ADR 0023 (`Host` includes the four `tcp_*` methods and `set_timer -> Result<TimerId, AppError>`)
  - `pub mod net { pub struct NetPolicy; impl NetPolicy { pub fn parse(&str) -> Result<Self, String>; pub fn allows(&self, IpAddr, u16) -> bool; pub fn is_empty(&self) -> bool } }` (moved verbatim from `wyrm-wasm-host`, `core::net` only)

- [ ] **Step 1: Write the failing tests** `app_error_cbor_roundtrip` (status `permission_denied`, msg `"no grant on wy/s/downstream/x"` survives `to_cbor`/`from_cbor`; garbage bytes → `Status::InternalError`), `who_may_uses_longest_prefix` (grants `[("wy/s/downstream/**", Read), ("wy/s/downstream/plc/**", Write)]`: `may("wy/s/downstream/plc/p1/~set", Write)` true, `may("wy/s/downstream/x/~set", Write)` false).
- [ ] **Step 2: Run** `cargo test -p wyrm-link-api` — expect compile failure (crate missing).
- [ ] **Step 3: Create the crate and types; move `NetPolicy`** (wasm-host re-exports it; its tests keep passing unchanged).
- [ ] **Step 4: Run** `cargo test -p wyrm-link-api -p wyrm-wasm-host` — PASS; `rustup target add wasm32-unknown-unknown && cargo build -p wyrm-core -p wyrm-link-api --target wasm32-unknown-unknown` — builds.
- [ ] **Step 5: Commit** `wyrm-link-api: portable App/Host traits, boundary types, NetPolicy (ADR 0023)`

### Task 2: `BufferHost` — the one command buffer every host uses

**Files:**
- Create: `crates/wyrm-link-api/src/buffer.rs`
- Test: same file (unit)

**Interfaces:**
- Consumes: Task 1 types.
- Produces:
  - `pub enum Command { DeclareNode(String, NodeMeta), DeclareAction(String, String, ActionMeta), RemoveNode(String), Update(String, Sample), SetTimer(TimerId, u64 /*after_ms*/), CancelTimer(TimerId), StorePut(String, Vec<u8>), StoreDelete(String), Subscribe(SubId, String), Unsubscribe(SubId), Set(ReqId, String, Value), Invoke(ReqId, String, String, Value), Log(Level, String) }`
  - `pub trait Services { fn now_us(&self) -> u64; fn store_get(&self, key: &str) -> Option<Vec<u8>>; fn store_used(&self) -> u64; fn may(&self, key: &str, perm: Perm) -> bool; fn tcp_connect(&mut self, addr: &str, port: u16, timeout_ms: u32) -> Result<ConnId, AppError>; fn tcp_send(&mut self, c: ConnId, d: &[u8]) -> Result<(), AppError>; fn tcp_recv(&mut self, c: ConnId, max: u32, timeout_ms: u32) -> Result<Vec<u8>, AppError>; fn tcp_close(&mut self, c: ConnId); }`
  - `pub struct Limits { pub max_nodes: usize, pub max_timers: usize, pub max_subs: usize, pub max_inflight: usize, pub max_commands: usize, pub store_bytes: u64 }` with `Default` = Global Constraints values
  - `pub struct Counts { pub nodes: usize, pub timers: usize, pub subs: usize, pub inflight: usize }` (owned by the runtime, passed in)
  - `pub struct BufferHost<'a> { … }` with `BufferHost::new(services: &'a mut dyn Services, limits: &'a Limits, counts: Counts, next_id: &'a mut u64, site_prefix: &'a str) -> Self`, `impl Host for BufferHost<'_>`, `fn finish(self) -> Result<Vec<Command>, AppError>`
  - Rules: `store_get` reads the event's own pending puts/deletes first; `set_timer`/`subscribe`/`set`/`invoke`/`store_put` check bounds and return `resource_exhausted`; `subscribe`/`set`/`invoke` check `services.may(key, Read|Write|Read)` and that `key` starts with `site_prefix` (`wy/<site>/`) else `permission_denied`; the 1 001st command of an event is refused with `resource_exhausted` (void commands are dropped and a flag makes `finish` return `Err(AppError)`); ids come from `next_id` (monotonic across events and restarts of the same runtime).

- [ ] **Step 1: Write the failing tests** `store_reads_its_own_writes` (put `"a"=[1]`, get `"a"`→`[1]`, delete, get→`None` within one buffer), `store_put_over_quota_is_refused` (`store_bytes=10`, `store_used()=8`, put 3 bytes → `resource_exhausted`, no `StorePut` in `finish()`), `bounds_on_timers_and_commands` (`max_timers=1`: second `set_timer` → `resource_exhausted`; 1 001 `update`s → `finish()` is `Err` with `resource_exhausted`), `requests_check_grants_and_site` (`may` false → `set` gives `permission_denied`; key `wy/other/…` → `permission_denied`; allowed → `Ok(ReqId)` and a `Set` command).
- [ ] **Step 2: Run** `cargo test -p wyrm-link-api buffer` — FAIL (module missing).
- [ ] **Step 3: Implement `buffer.rs`.**
- [ ] **Step 4: Run** `cargo test -p wyrm-link-api` — PASS; wasm32 build still passes.
- [ ] **Step 5: Commit** `wyrm-link-api: BufferHost, one command buffer for every host`

### Task 3: SDK — grants to the link, public sealing

**Files:**
- Modify: `crates/wyrm-link-sdk/src/runtime.rs` (`LinkConfig.grants: Vec<(String, Perm)>`), `crates/wyrm-link-sdk/src/ctx.rs` (`pub fn grants(&self) -> &[(String, Perm)]`), `crates/wyrm-link-sdk/src/process.rs` (`Hello.grants` parsed from `"grants": [[path, code], …]`), `crates/wyrm-link-sdk/src/driver/persist.rs` (extract `pub fn seal(key: &[u8;32], plain: &[u8]) -> Vec<u8>` and `pub fn open(key: &[u8;32], sealed: &[u8]) -> Option<Vec<u8>>` into new `crates/wyrm-link-sdk/src/seal.rs`, persist uses them), `crates/wyrm-admin/src/control.rs` (`hello` reply adds `"grants"` from `LinkDef::grants` with `{site}` expanded; embedded start sets `LinkConfig.grants` the same way)
- Test: `crates/wyrm-link-sdk/src/process.rs` (unit), `crates/wyrmd/tests/e2e.rs` (extend `link_grants_make_a_requester`)

**Interfaces:**
- Produces: `LinkConfig::grants`, `LinkCtx::grants()`, `Hello::grants`, `wyrm_link_sdk::seal::{seal, open}`.

- [ ] **Step 1: Write the failing tests** `hello_carries_grants` (parse a hello map with `grants: [["wy/s/downstream/mock", 3]]` → `Hello.grants == [("wy/s/downstream/mock", Write)]`), `seal_roundtrip_and_tamper` (open(seal(x)) == x; one flipped byte → `None`); in e2e `link_grants_make_a_requester` assert the process link's `LinkCtx::grants()` (exposed through its test tree value or a log line already asserted there) contains the granted path.
- [ ] **Step 2: Run** `cargo test -p wyrm-link-sdk hello_carries_grants seal_roundtrip` — FAIL.
- [ ] **Step 3: Implement** the fields, parsing, admin reply and embedded `LinkConfig.grants`.
- [ ] **Step 4: Run** `cargo test -p wyrm-link-sdk -p wyrm-admin && cargo test -p wyrmd --test e2e link_grants_make_a_requester` — PASS.
- [ ] **Step 5: Commit** `Links know their grants (hello, LinkConfig); sealing helpers are public`

### Task 4: `wyrm-link-portable` — runtime, store, native engine

**Files:**
- Create: `crates/wyrm-link-portable/Cargo.toml` (deps: `wyrm-link-api`, `wyrm-link-sdk`, `wyrm-client`, `wyrm-core`, `tokio`, `tracing`), `src/lib.rs` (re-exports), `src/engine.rs` (`Engine`, `Event`, `Fault`), `src/native.rs` (`NativeEngine<A>`), `src/runtime.rs` (`Runtime<E>`: `impl Link`), `src/store.rs` (sealed KV), `src/services.rs` (`Services` impl: clock, store, grants, blocking TCP with `NetPolicy`)
- Modify: `Cargo.toml` (workspace member/dependency)
- Test: `crates/wyrm-link-portable/tests/native.rs` (uses `wyrm_link_sdk::harness::TestHarness`)

**Interfaces:**
- Consumes: Tasks 1–3.
- Produces:
  - `pub enum Event { Set { path: String, value: Value, who: Who }, Invoke { path: String, action: String, args: Value, who: Who }, Timer(TimerId), Value(SubId, String, Sample), Reply(ReqId, Result<Value, AppError>), Stop }`
  - `pub enum Fault { Crash(String) /*panic, trap, fuel, memory, time*/ }`
  - `pub trait Engine: Send + 'static { fn name(&self) -> String; fn version(&self) -> String; fn start(&mut self, host: &mut BufferHost, config: &Value) -> Result<Result<(), AppError>, Fault>; fn event(&mut self, host: &mut BufferHost, ev: Event) -> Result<Result<Option<Value>, AppError>, Fault>; fn reset(&mut self); }` (`reset` drops the instance before a restart)
  - `pub struct NativeEngine<A: App> { app: Option<A> }`: calls under `std::panic::catch_unwind(AssertUnwindSafe(..))`; a panic → `Fault::Crash`.
  - `pub struct PortableConfig { pub params: Value, pub net: NetPolicy, pub store_mb: u32, pub call_ms: u32 }` with `FromParams` reading `params` (map), `net` (string, ADR 0012 syntax), `store_mb`, `call_ms` from the link's params (keys `net`, `store_mb`, `call_ms` are removed before `params` reaches the app).
  - `pub struct Runtime<E: Engine>`; `pub type Portable<A> = Runtime<NativeEngine<A>>;` with `impl<A: App + Send + 'static> wyrm_link_sdk::Link for Portable<A>` (`NAME`/`VERSION` from `A`) and a constructor trait `pub trait MakeEngine { type E: Engine; fn make(cfg: &PortableConfig, ctx: &LinkCtx) -> Result<Self::E, LinkError>; }` so `links/wasm` can supply `WasmEngine`.
  - Store: `<data_dir>/store/<hex(sha256(key))>` files sealed with the `.store_key` secret, atomic write (tmp + rename + fsync dir); no `data_dir` or key → `store_put` fails `not_supported`.
  - Behaviour per ADR 0023: engine on its own OS thread (`std::thread`), events over a bounded `sync_channel(256)`; full queue: coalesce `Value` per `SubId`, `Set`/`Invoke` answer `busy`; commands applied in order by the async side; apply failure → error reply + restart; restart backoff and 10 s re-declare sweep (nodes not re-declared removed; values marked `bad/comm_fail` at fault); root `""` gets `attr.status` (`running|restarting|stuck`) and `attr.error`; `stuck` after 30 s without a completed event; subscriptions via `WyrmClient::subscribe` with `SigningTokens` from `ctx.requester_key()` (current value first); `set`/`invoke` via `WyrmClient` with the same tokens, replies as `Event::Reply`; timers `tokio::time::sleep` (monotonic).

- [ ] **Step 1: Write the failing tests** in `tests/native.rs` with a test app `Echo` (declares `n` number writable and action `ping`; `on_set` stores the value with `store_put("n")` and `update`s it; `on_invoke("ping")` sets a 50 ms timer and returns `"pong"`; `on_timer` updates `ticks`; `start` restores `n` from the store; panics when it receives value `-1`):
  - `tree_set_invoke_timer` — after start, `~meta` lists `n`, `ticks`, action `ping`; `set n=5` → `~val` 5; `invoke ping` → `"pong"`; within 500 ms `ticks` == 1.
  - `store_survives_restart_and_quota_holds` — `set n=7`, stop and start the harness with the same `data_dir` → `n` reads 7; with `store_mb=0` the `set` fails `resource_exhausted`.
  - `panic_restarts_with_backoff_and_sweeps` — `set n=-1` → error reply; root `attr.status` becomes `restarting`, then `running` within 3 s; `n` still 7; a node the new `start` does not declare is gone after 10 s (use a `Echo` variant flag).
  - `panic_in_start_backs_off` — an app that always panics in `start`: after 4 s at most 3 starts happened (1 s, 2 s backoff), the broker side stays up.
  - `requests_outside_grants_are_refused` — app with `LinkConfig.grants = [("wy/s/downstream/mock/**", Write)]`: `set("wy/s/downstream/mock/p", 1)` reaches a mock link; `set("wy/s/downstream/other/p", 1)` and `subscribe("wy/x/downstream/mock/p")` → `permission_denied` from the `Host` call.
- [ ] **Step 2: Run** `cargo test -p wyrm-link-portable` — FAIL (crate missing).
- [ ] **Step 3: Implement** `engine.rs`, `native.rs`, `store.rs`, `services.rs`, `runtime.rs`.
- [ ] **Step 4: Run** `cargo test -p wyrm-link-portable` — PASS; clippy clean.
- [ ] **Step 5: Commit** `wyrm-link-portable: one runtime for portable links, native engine (ADR 0023)`

### Task 5: WIT `wyrm:app` and the guest crate

**Files:**
- Create: `crates/wyrm-wasm-host/wit/app/app.wit` (package `wyrm:app@0.1.0`, interface `host`, world `app`, exactly the ADR 0023 text), `crates/wyrm-link-guest/Cargo.toml` (`wit-bindgen = "=0.57.1"`, `wyrm-link-api`, `wyrm-core`; `crate-type` unchanged — the app crate is the cdylib), `crates/wyrm-link-guest/src/lib.rs` (`GuestHost: Host` over the generated imports; `#[macro_export] macro_rules! export { ($app:ty) => { … } }` implementing the generated `Guest` exports for `$app` in a `static` cell)
- Modify: `Cargo.toml` (member + dependency)
- Test: `crates/wyrm-link-guest/tests/build.rs` (builds a fixture app crate for `wasm32-unknown-unknown` with `cargo` and checks the core module's custom section `component-type:app` exists)

**Interfaces:**
- Consumes: Task 1 (`App`, `Host`, `AppError`, `Who`).
- Produces: `wyrm_link_guest::export!(MyApp)`; the WIT path `crates/wyrm-wasm-host/wit/app/app.wit` (used by Task 6 bindgen and Task 7 componentization).
- Guest rules: the exported functions decode CBOR with `wyrm-core` and call the app; a stored `App` instance lives in a `static RefCell<Option<A>>` (single-threaded wasm); `GuestHost` maps import errors (CBOR `{status,msg}`) to `AppError`.

- [ ] **Step 1: Write the failing test** `guest_fixture_builds_with_component_type` (fixture at `crates/wyrm-link-guest/tests/fixture/` = a 20-line `App` + `export!`).
- [ ] **Step 2: Run** `cargo test -p wyrm-link-guest` — FAIL.
- [ ] **Step 3: Write the WIT and the guest crate.**
- [ ] **Step 4: Run** `cargo test -p wyrm-link-guest` — PASS (the test skips with a clear message only if `wasm32-unknown-unknown` is not installed; CI installs it via `rust-toolchain.toml`).
- [ ] **Step 5: Commit** `wyrm:app world and the guest crate (ADR 0023)`

### Task 6: `WasmEngine` and driver `app` in `links/wasm`

**Files:**
- Modify: `crates/wyrm-wasm-host/src/lib.rs` (new `AppWorld` via `wasmtime::component::bindgen!` on `wit/app/app.wit`; `impl World for AppWorld` with `IMPORT = "wyrm:app/host@0.1.0"`; `pub struct AppRunner` with `start(&mut self, cfg) / call_event(..)` returning `Result<…, Error>`; store data holds a `HostState { services: Box<dyn Services + Send>, buffer state }` and the import impls delegate to a `BufferHost` built per call; `Error::{Fuel,Memory,Time,Trap}` map to `Fault::Crash`), `links/wasm/Cargo.toml` (+ `wyrm-link-portable`, `wyrm-link-api`), `links/wasm/src/app.rs` (new: `WasmEngine: Engine`, `impl MakeEngine for WasmEngine` loading `<root>/<package>.wasm` into an `AppWorld` `Slot` from the link params `component`), `links/wasm/src/lib.rs` (`pub mod app; pub type App = Runtime<WasmEngine>;`), `crates/wyrmd/src/lib.rs` (driver `"app"` and `pkg:` links whose package world is `app` → `start_boxed::<wyrm_link_wasm::App>`)
- Test: `links/wasm/tests/app.rs`

**Interfaces:**
- Consumes: Tasks 2, 4, 5.
- Produces: driver name `"app"`; `wyrm_link_wasm::App`; `wyrm_wasm_host::{AppWorld, AppRunner}`; component hot swap through the existing `Slot::swap`.

- [ ] **Step 1: Write the failing tests** (the `Echo` app of Task 4 built as a component by the test with `cargo build --target wasm32-unknown-unknown` + `wit_component::ComponentEncoder`, as Task 7's code; until then a helper in the test does the same): `same_scenario_as_native` — the four Task 4 scenarios run against `Runtime<WasmEngine>` give the same tree, values, replies and errors; `trap_fuel_memory_time_restart` — guest variants that trap, loop, and grow memory past 64 MiB each end in `restarting` → `running`, broker session alive; `hot_swap_keeps_store_and_fails_inflight` — swap the slot while a slow `invoke` runs: that `invoke` gets `busy`, `n` from the store is the same after the swap.
- [ ] **Step 2: Run** `cargo test -p wyrm-link-wasm --test app` — FAIL.
- [ ] **Step 3: Implement** `AppWorld`/`AppRunner`, `WasmEngine`, driver registration.
- [ ] **Step 4: Run** `cargo test -p wyrm-link-wasm -p wyrm-wasm-host` — PASS (existing `point`/`driver` tests unchanged).
- [ ] **Step 5: Commit** `WASM links on the app world: same runtime, same behaviour (ADR 0023)`

### Task 7: Packaging and install — `wyr link pack` for WASM, capabilities, `wyr new link --app`

**Files:**
- Modify: `crates/wyrm-link-sdk/src/package.rs` (`Manifest.capabilities: Option<Capabilities>`; `pub struct Capabilities { pub net: Vec<String>, pub store_mb: Option<u32>, pub memory_mb: Option<u32>, pub call_ms: Option<u32> }` with bounds checked in `Manifest::check`; `Manifest.world: Option<String>` = `"app"` for app components), `tools/wyr/Cargo.toml` (`wit-component = "=0.243.0"`), `tools/wyr/src/pack.rs` (`kind = "wasm"` in metadata: `cargo build --release --lib --target wasm32-unknown-unknown --features wasm`, componentize the `.wasm` with `wit_component::ComponentEncoder::default().module(&core)?.validate(true).encode()?`, pack with `world: "app"` and `capabilities` from metadata), `tools/wyr/src/scaffold.rs` + `tools/wyr/templates/link/app/{Cargo.toml.tmpl,lib.rs.tmpl,main.rs.tmpl,test.rs.tmpl}` (`wyr new link <name> --app`), `crates/wyrm-admin/src/packages.rs` + `control.rs` (a `wasm` package whose component exports `start`/`on-set` is `world: app` → link driver `pkg:<name>` started as `app`, params `{component, net, store_mb, call_ms, params}` from `capabilities`; `requester` grants as today), `docs/links.md` (section "Portable links"), `CLAUDE.md` (layout lines)
- Test: `tools/wyr/src/pack.rs` (unit), `crates/wyrmd/tests/e2e.rs` (`portable_app_installs_as_wasm`), `crates/wyrm-admin/src/packages.rs` (unit `install_picks_world_from_exports`)

**Interfaces:**
- Consumes: Tasks 4–6, ADR 0021 `wyr` code.
- Produces: `[package.metadata.wyrm-link] kind = "wasm"` + `capabilities = { net = [...], store_mb = N, memory_mb = N, call_ms = N }` + `requester = [...]`; `wyr new link <name> --app`.

- [ ] **Step 1: Write the failing tests** `plan_wasm_kind_reads_capabilities` (metadata `kind = "wasm"`, `capabilities.store_mb = 4` → manifest `world = Some("app")`, `capabilities.store_mb = Some(4)`; `store_mb = 65` → error), `install_picks_world_from_exports` (a `driver` component zip installs as framework `wasm`; an `app` component zip installs as `app`; a manifest saying `world: "app"` over a `driver` component is refused), e2e `portable_app_installs_as_wasm` (the scaffolded app packed by `wyr link pack`, installed from Zip, answers `invoke ping` with `"pong"` and keeps `n` across an upgrade), scaffold test `app_template_builds_and_passes` (as `generated_crates_build_and_pass`).
- [ ] **Step 2: Run** the four tests — FAIL.
- [ ] **Step 3: Implement** manifest fields, `wyr` build and componentize, install wiring, template, docs.
- [ ] **Step 4: Run** `cargo test -p wyr -p wyrm-admin && cargo test -p wyrmd --test e2e portable_app_installs_as_wasm` — PASS.
- [ ] **Step 5: Commit** `wyr link pack builds portable links as components; install grants their capabilities`

### Task 8: One app, three modes — example, demo check, benchmarks

**Files:**
- Create: `examples/links/portable/` (`wyrm-example-portable`: the `Echo` app as a real crate with features `process` and `wasm`, `[package.metadata.wyrm-link]`), `crates/wyrm-link-portable/benches/roundtrip.rs` (event round trip native vs WASM, restart time after a trap, memory per WASM instance)
- Modify: `examples/packages/build.sh` (pack it as process and as wasm), `crates/wyrmd/src/lib.rs` (register `Portable<wyrm_example_portable::Echo>` as driver `portable-echo` for the embedded mode test), `docs/links.md`, `examples/packages/README.md`
- Test: `crates/wyrmd/tests/e2e.rs` (`one_app_three_modes`)

**Interfaces:**
- Consumes: everything above.
- Produces: the reference portable link the scheduler plan (ADR 0022) copies.

- [ ] **Step 1: Write the failing test** `one_app_three_modes` — the same scenario (`set n`, `invoke ping`, `ticks` after the timer, `n` after a link restart) against the embedded driver `portable-echo`, the process package and the WASM package, with identical results.
- [ ] **Step 2: Run** it — FAIL.
- [ ] **Step 3: Create the example crate, registration, build.sh entries; write the bench.**
- [ ] **Step 4: Run** the e2e — PASS; `cargo bench -p wyrm-link-portable --bench roundtrip` prints the three numbers; `examples/packages/build.sh`, restart the demo, install both packages from the repository on edge, `wyr probe` on all three sites — 0 failed.
- [ ] **Step 5: Commit** `Portable example link in three modes; round-trip benchmarks`
