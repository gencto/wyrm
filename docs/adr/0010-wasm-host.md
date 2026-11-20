# ADR 0010 — WASM host for flow nodes (and later drivers)

**Status:** accepted · 2026-10-20

## Context
Principle 2 forbids dynamic Zenoh plugins; extensions come as data and processes. Iteration 8 adds sandboxed code: a flow node or a driver delivered as a WebAssembly component, loaded without a restart, unable to touch the host beyond what WYRM passes in.

## Decision
- `crates/wyrm-wasm-host`: wasmtime `=50.0.3` (the newest release line, pinned exactly; was `=40.0.4` until 2026-11-01 and `=36.0.20`, the LTS line, until 2026-11-20: see the note of 2026-11-20 below and ADR 0031 DEP-1), component model, no WASI. The linker is empty: a component that imports anything is refused at load (`Error::Denied`).
- WIT worlds (`crates/wyrm-wasm-host/wit/`): `wyrm:flow/node` — `init(config)`, `process(port, sample, state) -> (outputs, state)`; `wyrm:link/point` — `init`, `read`, `write`. All data is canonical CBOR (principle 5). The host keeps node state and passes it on every call, so a trap that destroys the instance never loses state.
- Limits per call: fuel (default 10 M, max 1 G), memory via a resource limiter (default 16 MiB, max 256 MiB), wall time via epoch interruption (100 ms, max 1 s). A trap drops the instance; the next call re-instantiates and re-runs `init`.
- Components are content-addressed: `put_artifact {bytes}` (flow engine root action, `config`) stores `<flow dir>/artifacts/<sha256>.wasm` (temp file + rename, hash checked on every read) and accepts only `wyrm:flow/node` components without imports. A `~def` node is `{type: "wasm", artifact: "<sha256>", inputs, outputs, config, fuel, memory_mb}`.
- Hot load = `put_artifact` + `deploy`: the flow hot-swaps (no process restart).

## Consequences
- A guest cannot open files, sockets or clocks; capabilities (`net:*`, `secrets:*`) are a later, explicit host-import design.
- Guest calls run synchronously on a tokio worker for up to the time limit.
- `validate` (`read`) loads the artifact and runs `init`; bounded by the limits and the per-caller invoke rate limit.
- Not yet: driver-framework integration of `wyrm:link/point`, artifact list/remove, per-node time limit, metrics for fuel and errors, `placement: "wasm"` from spec 06.

## Alternatives
- **wasmer / wasm3:** rejected; wasmtime has the component model, fuel and epoch interruption.
- **WASI preview 2 with a deny-all policy:** rejected for now; an empty linker is simpler to audit.
- **Core modules with a hand-made ABI:** rejected; WIT gives typed, versioned interfaces.

## Note of 2026-11-20: wasmtime 36.0.20 → 50.0.3
Three advisories of 2026-11-16 made `cargo audit` fail on 36.0.20 (RUSTSEC-2026-0566, -0569, -0571; fixed in 36.0.21). The owner's rule is the newest version of a dependency, not the oldest one that passes, so the host moved to the newest release line and not to 36.0.21. Two more advisories of that day exist only on the newer lines (RUSTSEC-2026-0567 from 39, -0573 from 47); 50.0.2 fixed all five.

- **Pin.** `=50.0.3`, features `runtime`, `cranelift`, `component-model`, `std` as before: no WASI, async, cache, GC, threads or profiling. The `wasm-tools` crates (`wasmparser`, `wit-component`, `wit-parser`) follow it to 0.261, the version wasmtime 50 is built on.
- **Rust.** wasmtime 50 needs Rust 1.97, so the workspace `rust-version` went from 1.89 to 1.97. CI and the container images build with stable (1.99 and later).
- **Code.** The engine API the host uses (`Config`, `Store` limiter, fuel, epochs, `component::Linker`, `bindgen!`) did not change. Two calls of the `wasm-tools` crates did: an import or export name is now a structure (`full_name()`), and `embed_component_metadata` takes `canonical_names` (false).
- **WebAssembly features.** The engine's defaults grew between 36 and 50: wasmtime 50 turns on the GC proposal, function references and wide arithmetic, and a build without the `gc` cargo feature removes only the GC *types* and exceptions. So with a default `Config` a guest could use typed function references (`call_ref`), function subtypes, `ref.test`, `ref.cast`, `i31` and `i64.add128`, none of which 36 took. That is the path of RUSTSEC-2026-0570 (a guest aborts the process of a build without `gc`; fixed in 50.0.2). An abort is no trap: it ends the broker with every link. **Rule:** the host names every feature a guest may use (`GUEST_FEATURES` in `crates/wyrm-wasm-host/src/lib.rs`) and `Host::new` turns these on and every other feature off (`Config::wasm_features` with the set and with its complement), so the engine's defaults decide nothing and an upgrade cannot widen the set. The set is what 36.0.20 took: WebAssembly 2.0 (mutable globals, sign extension, saturating conversions, multi-value, bulk memory, reference types with `funcref` only, SIMD), multi-memory, relaxed SIMD, tail calls, extended constants, 64-bit memories, the component model. Multi-memory and 64-bit memories stay: they were on, installed components may use them, and the memory limit counts all memories of an instance together (the limiter sees every growth). Off, among others: GC, function references, `externref`, exceptions, threads, wide arithmetic, stack switching, custom page sizes, compact imports, every component-model extension (async, `map`, `implements`). RUSTSEC-2026-0567 (atomics in a build without `threads`) and -0573 (GC heap with a set reservation) are not reachable for the same reason, and 50.0.3 has all three fixes. A feature is added only with a guest that needs it, a test and a line here. Tests: `features_outside_the_set_are_refused_at_load` (it fails on a default `Config`), `features_of_the_set_load_and_run`, `an_import_that_only_implements_a_known_interface_is_refused`.
- **What the guest toolchain needs.** Checked on 2026-11-20 with this set: the 11 WASM packages of `wyr repo build --form wasm` (alarm, dql, dynamodb, influxdb, mongodb, mysql, postgres, scheduler, slack, telegram, uplink) and `portable-echo` of `wyr link pack`, all built with `wyrm-link-guest` (wit-bindgen 0.57.1) for `wyrm:app@0.3.0`, load on the host. The test `built_packages_load` repeats the check on a directory of unpacked packages (`WYRM_WASM_PACKAGES`); run it after an engine upgrade or a change of the set.
- **Host calls.** The engine bounds what one call from a guest may make the host allocate for its arguments ("hostcall fuel"; default 128 MiB in wasmtime 50, 2 GiB in 36). The host sets it to the instance's memory limit (`Limits::memory_bytes`, 16 MiB by default): a guest cannot hold more than that, so no call that fits the memory limit is refused, and the bound follows the limit instead of the engine's default.
- **Limits.** Memory, time and import refusals behave as before, with the same error texts. Fuel is counted a little differently (wasmtime 46 charges a bulk memory instruction by its size, 50 charges more host allocations): one call of the test node `add` uses 207 units, was 200. The defaults stay.
- **Compiled code.** The host compiles a component in memory at load and keeps it by SHA-256 for the life of the process. Nothing compiled is written to disk, so no file of an older engine can be loaded.
