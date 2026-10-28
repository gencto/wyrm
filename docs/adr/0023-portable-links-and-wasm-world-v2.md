# ADR 0023 — Portable links: one link API for embedded, process and WASM (WASM world v2)

**Status:** accepted · 2026-10-28 (owner approved the document with the builder-check resolutions; owner decisions in this conversation: WASM is for fault isolation and hot start of links an engineer or integrator installs, not a sandbox for hostile code; a WASM link gets the full link API with capabilities granted at install; one source for all three run modes; this comes before the scheduler, ADR 0022).

## Context
A WASM link today (ADR 0010, 0012) is a polled point driver: `init`, `read`, `write`, plus outbound TCP to an allowlist. It has no node tree of its own, no actions, no clock, no timers, no storage and cannot write other points. That fits a third-party protocol driver in a sandbox, not the owner's goal: install a link (a scheduler, a calculation, a gateway to some protocol) so that whatever happens to it, the broker keeps running, and replace it without restarting the broker.

The native SDK (`trait Link`, `LinkCtx`) is async and hands drivers a raw Zenoh session; it cannot run in a component as it is.

What already holds and stays: a trap, an out-of-memory, fuel exhaustion or a call over its time kills only that instance; the host instantiates again; `Slot::swap` replaces a component with no broker restart; no WASI.

## Goals
1. One link source builds as an embedded link, a process package and a WASM component (cargo features), with the same behaviour.
2. A WASM link has what a native link has: its own tree (nodes, values, actions, `set`), a clock, timers, a key-value store, subscriptions to other points and requests to them (`set`, `invoke`) within grants.
3. Every capability is granted explicitly at install; nothing else is reachable.
4. A misbehaving link never takes the broker down and comes back by itself (with backoff); its last good tree is not left behind half-declared.
5. Building a WASM link needs only `cargo` and `wyr` (no external `wasm-tools`/`cargo component`).

## Non-goals
- Hostile-code hardening beyond what exists (fuel, memory, time, no WASI, explicit imports). The trust model is "installed by someone with `config`".
- Streaming action replies and raw Zenoh access in the portable API (native links that need them keep `trait Link`).
- Rewriting existing links on the new API (they may move later).
- New network kinds (TLS, UDP, serial, DNS); the `tcp` interface of ADR 0012 is reused as it is.

## Decision

### The portable API (crate `wyrm-link-api`; depends on `wyrm-core` only; builds for `wasm32-unknown-unknown`)
An actor: the host calls the app one event at a time; the app answers synchronously and acts through a `Host` handle. No async in the app.

```rust
pub trait App: Sized {
    const NAME: &'static str;
    const VERSION: &'static str;
    fn start(host: &mut dyn Host, config: Value) -> Result<Self, AppError>;
    fn on_set(&mut self, host: &mut dyn Host, path: &str, value: Value, who: &Who) -> Result<(), AppError>;
    fn on_invoke(&mut self, host: &mut dyn Host, path: &str, action: &str, args: Value, who: &Who) -> Result<Value, AppError>;
    fn on_timer(&mut self, host: &mut dyn Host, timer: TimerId) {}
    fn on_value(&mut self, host: &mut dyn Host, sub: SubId, key: &str, sample: Sample) {}
    fn on_reply(&mut self, host: &mut dyn Host, req: ReqId, result: Result<Value, AppError>) {}
    fn stop(&mut self, host: &mut dyn Host) {}
}

pub trait Host {
    // tree (the app owns its subtree, principle 3)
    fn declare_node(&mut self, path: &str, meta: NodeMeta);
    fn declare_action(&mut self, path: &str, name: &str, action: ActionMeta);
    fn remove_node(&mut self, path: &str);
    fn update(&mut self, path: &str, sample: Sample);
    // time
    fn now_us(&self) -> u64;                       // wall clock, UTC µs
    fn set_timer(&mut self, after_ms: u64) -> Result<TimerId, AppError>;  // one-shot, monotonic
    fn cancel_timer(&mut self, t: TimerId);
    // storage (the link's own, survives restarts and upgrades)
    fn store_get(&self, key: &str) -> Option<Vec<u8>>;
    fn store_put(&mut self, key: &str, value: &[u8]) -> Result<(), AppError>;  // durable when the event returns
    fn store_delete(&mut self, key: &str);
    // other points, within grants
    fn subscribe(&mut self, key: &str) -> Result<SubId, AppError>;
    fn unsubscribe(&mut self, sub: SubId);
    fn set(&mut self, key: &str, value: Value) -> Result<ReqId, AppError>;     // reply via on_reply
    fn invoke(&mut self, key: &str, action: &str, args: Value) -> Result<ReqId, AppError>;
    // network, within the link's `net` allowlist (ADR 0012 rules in every host)
    fn tcp_connect(&mut self, addr: &str, port: u16, timeout_ms: u32) -> Result<ConnId, AppError>;
    fn tcp_send(&mut self, c: ConnId, data: &[u8]) -> Result<(), AppError>;
    fn tcp_recv(&mut self, c: ConnId, max: u32, timeout_ms: u32) -> Result<Vec<u8>, AppError>;
    fn tcp_close(&mut self, c: ConnId);
    fn log(&mut self, level: Level, msg: &str);
}
```
- **Effects are applied after the event returns**, in order (a command buffer), in every host: the same semantics native and WASM. Reads (`now_us`, `store_get`) are immediate, and `store_get` sees the event's own earlier `store_put`/`store_delete` (read your writes). `store_put` is durable when the event's commands are applied and before the reply to a `set`/`invoke` leaves. TCP calls are immediate (blocking, bounded by the call's time), as in ADR 0012.
- **An event fails as a whole:** if the app traps or runs out of fuel, memory or time during an event, its buffered commands are dropped. If applying a command fails (bad meta, a bound reached, the store full or its disk failing), the rest of that event's commands are dropped, a `set`/`invoke` gets that error (`resource_exhausted`, `invalid_parameter`, `internal_error`), and the instance is restarted so its memory and its store cannot disagree. Bounds are checked when a command is buffered too, so the app sees `resource_exhausted` from the `Host` call itself where it can (`set_timer`, `subscribe`, `set`, `invoke`, `store_put` return `Result`).
- **Replies:** `on_invoke` answers synchronously; there is no deferred reply in this version (an app that must ask another point first answers with what it has, or the caller polls). Streaming stays out.
- **Timers are monotonic** (`set_timer` counts elapsed time, unaffected by clock steps); `now_us` is the wall clock. An app compares the two to detect a clock step (ADR 0022).
- **Subscriptions** deliver the point's current value first (as `wyrm-client` `subscribe`), then changes. A full event queue coalesces `on_value` per subscription (the newest sample wins); `set`/`invoke` are never dropped: when the queue is full they get `busy`.
- **Errors** carry a WYRM status and a message (`AppError { status, msg }`); `who` carries the verified subject and grants of the caller (for checks such as ADR 0022's targets).
- **Requests to other points** are refused at once (`permission_denied`) when no grant covers them; grants are the link's (below).

### Three hosts
- **Native adapter** `Portable<A: App>` in `wyrm-link-sdk` implements `trait Link`: one task owns `A`; SDK callbacks, tokio timers, subscriptions and replies become events; commands map to `LinkCtx`; requests are signed with the link's requester key (ADR 0013) or, for an embedded link the admin keys, with that link's own key. The store is a sealed file in the link's `data_dir` (one record per key, atomic replace), as `driver::persist`.
  - Embedded: registered in `wyrmd` as any driver (`Portable<A>`).
  - Process: `process::main::<Portable<A>>()` (ADR 0021).
- **WASM host** (new world, driver `app` in `links/wasm`): the component runs on one OS thread that owns its store; events arrive over a bounded channel; each event is one guest call under the existing limits (fuel, memory, epoch time; default 2 s per call, at most 10 s), and its returned commands are applied by the thread through `LinkCtx`. Imports are the `host` interface below and, when granted, `tcp` (ADR 0012).
- **Guest crate** `wyrm-link-guest`: implements `Host` over the imports and exports the world for an `App` with one macro, `wyrm_link_guest::export!(MyApp)`.

### WIT: package `wyrm:app@0.1.0`, world `app` (a new package: `wyrm:link@0.1.0` with `point`, `driver` and `tcp` stays byte for byte, so existing components keep loading)
```wit
interface host {
  declare-node: func(path: string, meta: list<u8>);            // CBOR ~meta
  declare-action: func(path: string, name: string, action: list<u8>);
  remove-node: func(path: string);
  update: func(path: string, sample: list<u8>);                 // CBOR ~val {0:v,1:q,2:t}
  now-us: func() -> u64;
  cancel-timer: func(id: u64);
  store-get: func(key: string) -> option<list<u8>>;
  // errors are CBOR {status, msg}, as the exports' (no status lost on the boundary)
  set-timer: func(after-ms: u64) -> result<u64, list<u8>>;
  store-put: func(key: string, value: list<u8>) -> result<_, list<u8>>;
  store-delete: func(key: string);
  subscribe: func(key: string) -> result<u64, list<u8>>;
  unsubscribe: func(id: u64);
  set: func(key: string, value: list<u8>) -> result<u64, list<u8>>;
  invoke: func(key: string, action: string, args: list<u8>) -> result<u64, list<u8>>;
  tcp-connect: func(addr: string, port: u16, timeout-ms: u32) -> result<u32, list<u8>>;
  tcp-send: func(conn: u32, data: list<u8>) -> result<_, list<u8>>;
  tcp-recv: func(conn: u32, max: u32, timeout-ms: u32) -> result<list<u8>, list<u8>>;
  tcp-close: func(conn: u32);
  log: func(level: u8, msg: string);
}
world app {
  import host;   // always linked; a capability not granted fails its calls with permission_denied
  export start: func(config: list<u8>) -> result<_, list<u8>>;            // errors: CBOR {status, msg}
  export on-set: func(path: string, value: list<u8>, who: list<u8>) -> result<_, list<u8>>;
  export on-invoke: func(path: string, action: string, args: list<u8>, who: list<u8>) -> result<list<u8>, list<u8>>;
  export on-timer: func(id: u64);
  export on-value: func(sub: u64, key: string, sample: list<u8>);
  export on-reply: func(req: u64, result: result<list<u8>, list<u8>>);
  export stop: func();
}
```
All data on the boundary is canonical CBOR (principle 5); the guest uses `wyrm-core`'s codec. `declare-node`, `declare-action`, `remove-node` and `update` return nothing: a bad meta or a bound reached fails the event when the commands are applied (above). The installer tells an `app` component from a `point`/`driver` one by its exports.

### Capabilities, granted at install
The package manifest (ADR 0021, `[package.metadata.wyrm-link]`) gains `capabilities`:
- `net`: the `tcp` allowlist entries (ADR 0012 syntax) or `[]`;
- `requester`: grants on other points (ADR 0013 syntax; the existing field);
- `store_mb`: store size (default 1, at most 64);
- `limits`: `memory_mb` (default 64, at most 512), `call_ms` (default 2000, at most 10000).

Installing shows them and applies them as the link's settings. Later changes go the existing ways: requester grants through `sys/links/<id>/~act/grant` (ADR 0013, router rebuild), `net`, `store_mb` and `limits` through the link's `update` (params). A capability not granted fails its calls with `permission_denied`.
- **The link knows its grants:** the admin sends them in the `hello` reply (process) and in `LinkConfig` (embedded, WASM), so a request outside them is refused in the link before it reaches the router (the router ACL still refuses it too). Reading another point (`subscribe`) needs a `read` grant in every mode: ADR 0013's "embedded links read everything" is not used by portable links.
- **Embedded built-in apps** (the scheduler, ADR 0022) get their grants from `wyrmd` at start, not from an operator: the scheduler gets `write` on `wy/<site>/downstream` and signs with its own admin-made key (as the agent's); its own checks (ADR 0022 targets) narrow what a caller may make it do.

### Faults and restarts
The guarantees below hold for WASM in full. A process link gets them from the OS (a separate process, restarted by the supervisor with backoff). An embedded native app is trusted code shipped with `wyrmd` (the scheduler): the adapter runs it on its own thread and catches panics (restart with the same backoff and tree rules), but an endless loop in native code cannot be stopped; such a link is reported `stuck` (no event completed for 30 s) and needs a broker restart. Third-party code therefore runs as WASM or as a process, never embedded.
- A trap, out-of-memory, fuel exhaustion or a call over time: the host drops the instance, marks the link `restarting` (status node, as ADR 0004's state machine) with the error, waits (1 s, ×2, cap 60 s, jitter), instantiates again and calls `start`. Timers and subscriptions of the dead instance are dropped; the store is kept.
- The tree: before calling `start` again the host keeps the old tree but marks its values `bad/comm_fail`; nodes the new `start` does not declare again within 10 s are removed (re-declare, principle 3; no half tree left behind). The host's own nodes (the link status, as the framework's `status` and `error`) live in the link's `sys/links/<id>` node, never in the app's subtree, so the sweep never touches them; the app's paths may not start with `.`.
- **Config:** `start` gets the link's params (a CBOR map; the app validates it and fails `start` with `invalid_parameter` naming the field). A change of params is a stop and a start (no `reconfigure`).
- Hot start: a new component (package upgrade, "Install ▸ from WASM" again) goes through `stop` on the old instance (bounded 2 s), then the new one starts; the store carries over; requests in flight get `unavailable`.
- Bounds: at most 10 000 nodes, 1 000 timers, 1 000 subscriptions, 100 requests in flight, 1 000 commands per event; going over one fails that call with `resource_exhausted` (not a trap).

### Building: one crate, three outputs
```toml
[features]
process = ["wyrm-link-sdk/process"]       # bin: process::main::<Portable<App>>()
wasm = ["dep:wyrm-link-guest"]            # cdylib: wyrm_link_guest::export!(App)
[package.metadata.wyrm-link]
kind = "wasm"                              # or "process"; `wyr link pack --kind` overrides
capabilities = { requester = [...], store_mb = 4 }
```
- `wyr link pack` for `kind = "wasm"`: `cargo build --release --target wasm32-unknown-unknown --lib --features wasm`, then turns the core module into a component in-process with the `wit-component` crate (bindings from `wit-bindgen` in `wyrm-link-guest` carry the component type), then packs it (ADR 0021). One zip for every host.
- `rust-toolchain.toml` adds the target `wasm32-unknown-unknown`.
- `wyr new link <name> --app` scaffolds such a crate (lib with the `App`, `src/bin` for process, the `wasm` feature, a test on the native adapter).

### Tests and benchmarks
- One test app run on all three hosts with the same scenario (tree, `set`, `invoke`, timer, store across a restart, `set` on another point within and outside its grant), compared event by event.
- Faults: a guest that panics in `on_timer`, loops forever, allocates past its memory, keeps the broker up and comes back; a hot swap keeps the store.
- Benchmarks: event round trip (native vs WASM), memory per instance, restart time after a trap, commands per second.

## Consequences
- ADR 0022 (scheduler) is written as an `App`: its persistence is the host store, its timers and writes go through `Host`. That ADR is updated when this one is accepted.
- `wyrm-link-sdk` gains the adapter; `links/wasm` gains the `app` driver next to `wasm` (point/driver worlds unchanged).
- `wyrm-core` must keep building for `wasm32-unknown-unknown` (CI checks it).

## Left to the builder
- Crate names and module layout; whether `Portable<A>` lives in `wyrm-link-sdk` or its own crate.
- The exact CBOR of `who` and of `AppError`; the store's file format (sealed with the link's store key).
- The native adapter's thread and channel layout, within the rules above.
