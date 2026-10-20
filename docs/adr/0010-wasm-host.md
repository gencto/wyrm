# ADR 0010 — WASM host for flow nodes (and later drivers)

**Status:** accepted · 2026-10-20

## Context
Principle 2 forbids dynamic Zenoh plugins; extensions come as data and processes. Iteration 8 adds sandboxed code: a flow node or a driver delivered as a WebAssembly component, loaded without a restart, unable to touch the host beyond what WYRM passes in.

## Decision
- `crates/wyrm-wasm-host`: wasmtime `=40.0.4` (newest for MSRV 1.89), component model, no WASI. The linker is empty: a component that imports anything is refused at load (`Error::Denied`).
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
