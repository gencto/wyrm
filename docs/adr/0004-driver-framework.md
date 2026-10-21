# ADR 0004 — Driver framework inside wyrm-link-sdk

**Status:** accepted · 2026-10-20

## Context
DSA v2 connectors (reference: `dslink-java-v2-modbus` + `driver-framework-java-v2-prototype`) proved a concept worth keeping: a connector is a tree `Connection → Device → Point`, every level is an editable node with declarative parameters and `Add/Edit/Remove/Restart` actions, and a change at any level reactively rebuilds only what depends on it. The Java implementation has defects (non-atomic edits, races on reconnect, optimistic writes, unbounded backoff, silent config loss) that we must not port.

## Decision
`wyrm-link-sdk` ships two layers:

1. **Raw layer** — `trait Link`, `LinkCtx`, `NodeTree`, one queryable per link, liveliness, `ptok` check. For drivers with their own topology (MQTT, OPC UA browse, gateways).
2. **Driver framework** (`wyrm_link_sdk::driver`) — opinionated layer on top of (1) for protocol drivers. A driver declares node *kinds* and the framework provides everything else.

### What the framework provides
| Concern | Design |
|---|---|
| Parameters | One declarative schema per node kind: `#[derive(Params)]` on a config struct → name, type, enum, default, bounds, description, placeholder, `secret` flag. Generates `~meta.cfg` schema, `Add <Kind>` action form (pre-filled with defaults), `Edit` action (pre-filled with current), load-time validation, fuzz values for tests. Parameters are typed structs, parsed once, never string-keyed maps. **Amended 2026-10-22 (owner decision: node structure as in the DSA driver framework, `dslink-java-v2-modbus`):** a level may have several node kinds, as DSA's `Add IP Connection` beside `Add Serial Connection`: `#[derive(Params)]` on an enum of newtype variants gives one kind per variant (`Params::kinds`), each with its own `add_<kind>` action and form; the tree stores the node's `kind` beside its params on such levels (their params may not be named `kind`). Fields carry `display` (label), `desc` (description), `placeholder` and `editor`; a `secret` is a `password` field (spec 02 0.1.6). A driver may offer found values for a param (`Driver::choices`, e.g. serial ports) and a root `rescan` action (`Driver::RESCAN`, DSA "Rescan For Serial Ports"). |
| Edit semantics | **Validate first, atomically.** `validate(new) → Err` aborts with `invalid_parameter{path}` and nothing changes. Then `diff(old, new) → Rebuild::{None, Self, Subtree, Connection}` decides what restarts; drivers may override `on_edit(old, new)` for fine-grained reaction (e.g. only reschedule a point). Teardown with *old* config completes before bring-up with *new* — no async close racing a new open. |
| Lifecycle & liveness | Typed state machine per node: `New → Connecting → Connected → Failed → Stopped → StoppedByParent`. A child runs only while its parent is `Connected`; parent failure cascades `StoppedByParent`. Published as `~val` of the node (`status`) plus `~meta.q`. Never a free-form string. **Amended 2026-10-22:** `status` is an enum leaf (`wy:df-status`: Unknown, Connecting, Connected, Failed, Stopped, Stopped by Parent; `~val` = index), and the error text is a separate string leaf `error` (`wy:df-error`) that exists only while there is an error, as DSA's `Status` and `Error` values. |
| Scheduling | Per-connection **owner task** that exclusively holds the transport and consumes an mpsc of requests (ping, poll batch, write) — the Rust equivalent of a fair lock. Tick launches I/O only if the previous I/O finished (no pile-up). Backoff on failure: exponential with cap and jitter (`1s..60s`, ±20 %). |
| Polling | Points are polled **all the time** by default (amendment 2026-10-20, owner decision: the in-process `~val` storage of `wyrmd` always counts as a subscriber, and reads must be fresh); `poll_unsubscribed: false` polls only while subscribed (SDK knows subscriber count per key; reliable for process links only). Points grouped into batches by `(device, poll_rate)`; batch plan (address partitioning, max read count, contiguity) is **cached** and invalidated on edit, not rebuilt every tick. Per-point errors are distinct from whole-batch transport failure. |
| Writes | `~set` is a request/response: no optimistic update. Framework calls `write(point, value)`; `~val` is updated only from read-back (immediate read after write, or next poll) with the write's status returned in attachment. Write strategy knob per connection (`single|multiple|auto`). |
| Quality | Timeout → `uncertain/stale` for N misses, then `bad/comm_fail`; parent down → `bad/disconnected`; recovery → `good`. Exact codes in attachment key 1. |
| Persistence | **Amended 2026-10-21 (owner decision: the connector owns its config, credentials come with the connection as in DSA).** The framework keeps the whole tree, secret fields included, in the link's `data_dir/framework.tree`, sealed with ChaCha20-Poly1305 under the link's store key (secret `.store_key`, created by the admin per link and delivered with the link secrets), and writes it after every `add_*`/`edit`/`remove`/`enable`/`disable`. `~def.params` is the bootstrap: the file stores its SHA-256, and new bootstrap params (json5 edit, admin `update`/`rollback`) replace the stored tree. A file that does not open (other key, tampering) falls back to the bootstrap. Without a `data_dir` or store key the tree lives in memory. Secret params (`#[param(secret)]`) never show in `~meta.cfg`, `export` or replies; an `edit` that leaves a secret empty keeps the stored one only while the destination fields (`#[param(dest)]`, or every field when none is marked) stay the same. Load-time validation failure **keeps the node** in `Failed` with `~val.error`, never deletes it. |
| Slave/server mode | Optional trait `ServerKind` for drivers that can expose the tree as a protocol server (Modbus slave, OPC UA server): shared listener per port keyed by `(transport, port)`, process image per unit, ref-counted shutdown, strict duplicate/overlap rejection at registration. |
| Actions | `Add <Kind>`, `Edit`, `Remove`, `Restart`, `Start/Stop` generated per kind; `Start/Stop` only on branches, not on points. Drivers add their own (`Rescan ports`, `Discover`). **Amended 2026-10-22:** as in DSA, only the action that applies is declared: `stop` while the node runs, `start` while it is stopped. Every action has a name for people and a menu group (spec 02): `add_*` → `new`; `edit`, `remove` → `edit`; `restart`, `start`/`stop`, `export`, `rescan` → top level. |
| Observability | Per-node metrics (`rtt_ms`, `errors`, `polls`), rate-limited logs with `link=/node=` fields, state transitions audited. |

### Driver surface (what a Modbus driver writes)
```rust
#[derive(Params)] struct IpConn { host: Ip, port: u16 = 502, timeout_ms: u32 = 500 @bounds(100..=10000), retries: u8 = 2, write_mode: WriteMode = Auto, ping_s: f64 = 5.0 }
#[derive(Params)] struct Device  { unit: u8 @bounds(1..=247), ping_s: f64 = 5.0, contiguous_only: bool = false }
#[derive(Params)] struct Point   { kind: Reg = Holding, addr: u16, dtype: DType = U16, bit: u8 = 0, regs: u8 = 1, poll_s: f64 = 5.0, scale: f64 = 1.0, offset: f64 = 0.0 }

impl Connection for ModbusTcp { async fn open(&IpConn) -> Transport; async fn ping(&mut self) -> Result<()>; }
impl Device for ModbusDevice  { fn plan(points) -> BatchPlan; async fn poll(&mut self, plan) -> Vec<(PointId, Result<Raw>)>; async fn write(&mut self, point, value) -> Result<()>; }
impl PointKind for ModbusPoint { fn decode(raw) -> Value; fn encode(value) -> Raw; fn value_type() -> TypeCode; }
```
Everything else — tree, actions, edit, states, scheduling, subscription gating, quality, metrics — is the framework.

## Consequences
- Drivers are ~300–600 lines and behave identically to operators (same actions, same states, same error reporting).
- `links/mock` is the first framework driver; `links/modbus` the first real one. BACnet/DLMS reuse the same kinds with discovery actions.
- The framework adds iteration-1 scope; `wyrm-link-sdk` is delivered in two steps: raw layer, then `driver` module before `links/modbus`.
