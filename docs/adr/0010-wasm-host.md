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
- **Proposals.** A build without `gc` and `threads` refuses GC types, exceptions and shared memory at load, and the host turns no proposal on by hand. RUSTSEC-2026-0567 (abort on atomics in a build without `threads`) needs `Config::wasm_features` to turn threads on; RUSTSEC-2026-0573 needs a GC heap with a set reservation. Neither is reachable here, and 50.0.3 has both fixes. The `implements` names of the component model are off in the engine; an import is refused by its own name in any case. Tests: `proposals_outside_the_build_are_refused_at_load`, `an_import_that_only_implements_a_known_interface_is_refused`.
- **Limits.** Memory, time and import refusals behave as before, with the same error texts. Fuel is counted a little differently (wasmtime 46 charges a bulk memory instruction by its size, 50 charges more host allocations): one call of the test node `add` uses 207 units, was 200. The defaults stay.
- **Compiled code.** The host compiles a component in memory at load and keeps it by SHA-256 for the life of the process. Nothing compiled is written to disk, so no file of an older engine can be loaded.
