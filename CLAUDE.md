# WYRM — project context for Claude Code

Broker with IOT-DSA semantics (node tree, reactive list/subscribe/invoke, managed connectors, data-flow) on top of Eclipse Zenoh 1.x as transport. One Rust binary `wyrmd` = Zenoh runtime (router) + static plugins. Zenoh is never patched or forked.

## Language and docs
- Code, comments, commit messages: English. Design wiki (Obsidian, outside this repo at `~/Documents/Obsidian/Wiki/Zenoh`) and discussions with the owner: Ukrainian.
- `spec/` is **normative**. Any change there → update `spec/fixtures/gen.py` → regenerate → every SDK's fixture test must pass → line in `spec/CHANGELOG.md`.
- Decisions go to `docs/adr/NNNN-*.md`. Read ADR 0001–0005 before touching architecture; ADR 0004 (driver framework) is mandatory reading before writing any `links/*`.

## Non-negotiable principles
1. Zenoh = transport; WYRM = semantics via key-space conventions, CBOR attachment, SDKs, static plugins.
2. No dynamic Zenoh plugins (`.so`): ABI lock-step with the router. Extend via data (`flows/**`) and processes (connectors).
3. **The broker owns only itself**: it persists control-plane state (registry, ACL, PKI, profiles, flow defs) via WAL + postcard snapshot. Connectors own and re-declare their subtree on every (re)connect. What is not re-declared does not exist.
4. Nobody reads another component's state directly — only `put/get/subscribe` on keys with attachment, even in-process.
5. One wire codec: canonical CBOR, integer keys, `minicbor`. `serde`/`json5` only for `wyrmd.json5`.
6. Security is not optional: TLS/mTLS everywhere except loopback/UDS; secrets never in the tree; `ptok` checked in responder SDK.

## Key-space (spec/01)
`wy/<site>/down/<link>/<path>/{~meta,~val,~set,~act/<a>}` · `flows/<id>/{~def,~meta,~val,nodes/<n>/…}` · `pub/<profile>/~meta` · `sys/**` (admin only). Full site names everywhere, no virtual prefixes. `list` = one level (`~meta?view=list`), `resolve` = keys only (`view=keys&match=`), pattern subscriptions for fan-in.

## Workspace layout (target)
```
crates/wyrm-core        ✅ types + codec + fixture test
crates/wyrm-link-sdk    trait Link, LinkCtx, NodeTree, one queryable per link, liveliness, TestHarness
crates/wyrm-client      list()/subscribe()/set()/invoke() as Streams
crates/wyrm-state       WAL (CBOR, HMAC-chain, CRC/record) + postcard snapshot
crates/wyrm-history     trait HistoryStore + host; history/{rocksdb,influxdb}
crates/wyrm-flow        engine: compiler, node registry, rhai, runtime
crates/wyrm-admin       registry, supervisor, tokens, CA, quarantine, ACL generator, gateway
crates/wyrmd            binary
links/{mock,modbus,mqtt,opcua,bacnet,dlms}   lib + bin (feature "bin")
tools/wyr               CLI (ops + dev: new/dev/sim/replay/ai/mcp)
tools/wyrm-mcp          MCP server over wyrm-client (ADR 0005)
links/agent             AI agent connector with approval workflow (ADR 0005)
```

## Current state
Iteration 0 done (2026-10-20): spec v0.1, `wyrm-core`, 22 fixtures green, CI config in `docs/ci.yml.pending` (move to `.github/workflows/ci.yml`).

## Next: Iteration 1 — core (in this order)
1. `wyrm-link-sdk` raw layer: `trait Link { start, reconfigure, on_set, on_invoke, stop }`, `LinkCtx { declare_node, declare_action, update, publisher, remove_node, set_dynamic, mark_all, client, secrets, metrics, subscriber_count }`; SDK declares ONE queryable on `wy/<site>/down/<link>/**`, routes by suffix, answers `~meta?view=list|keys|full`, checks `ptok` before calling the driver, sets liveliness; `TestHarness` with in-memory Zenoh runtime (`zenoh::Config` mode peer, no network).
1b. `wyrm-link-sdk::driver` framework (ADR 0004): `#[derive(Params)]` (schema, bounds, defaults, secret flag → `~meta.cfg` schema + generated `Add/Edit/Remove/Restart/Enable` actions), node kinds `Connection/Device/Point` traits, typed state machine (`New/Connecting/Connected/Failed/Stopped/StoppedByParent`) with parent→child cascade, per-connection owner task with mpsc (ping/poll/write serialized), poll batches by `(device, poll_rate)` with cached plan, **polling only while subscribed**, validate-then-diff edit (`Rebuild::{None,Self,Subtree,Connection}`), teardown-before-bringup, exponential backoff with cap+jitter, writes without optimistic update (read-back), quality ladder `good → uncertain/stale → bad/comm_fail`, load-time validation failure keeps node as `Failed` (never deletes config). Optional `ServerKind` for slave/server mode.
2. `links/mock`: first framework driver — N points × F Hz, configurable tree depth, injectable failures (timeouts, exception replies) — needed for every later test and for `wyr bench`.
3. `wyrm-client`: `list()` = subscribe `*/~meta` + liveliness `*` BEFORE `get ~meta?view=list` (no lost-update window), emit `Refreshed/Added/Changed/Removed/Disconnected`; `subscribe()` = `get ~val` (storage) + subscribe; `set/invoke` = `get` with payload + attachment.
4. `wyrmd` minimal: config → `zenoh::Config` built programmatically, router mode, storage-manager (`mem` on `**/~val`, `rocksdb` on `{flows,pub,sys}/**`), embedded `mock`. No admin/flow/TLS yet.
5. `tools/wyr`: `list`, `sub`, `set`, `invoke`, `bench` (p50/p95/p99 on subscribe and list-1000).
6. `links/modbus` on `tokio-modbus` using the driver framework: kinds `IpConn/SerialConn → Device → Point`; data types as in DSA (`BINARY, U16/I16(+swapped), U32/I32(+word/byte swapped), F32(+swapped), U64/I64, F64, BCD16/32, CHAR, VARCHAR`), bit index for BINARY on registers, linear scaling, FC1–4 batched reads partitioned by contiguity/max-count with `contiguous_only` escape hatch, writes FC5/6/15/16 + FC22 mask-write with RMW fallback cached per unit, `write_mode: auto|single|multiple`, device ping via FC17 or a configurable probe register (FC17 is often unsupported). Verified against `diagslave` and a real device. Slave mode (`ServerKind`) is iteration 6.

Later iterations (see wiki 07 План): 2 control-plane, 3 flow, 4 two brokers, 5 security, 6 connectors, 7 Dart/Flutter, 8 WASM, 9 platform (cloud profile, MCP, agent, dev CLI).

Iteration 1 is done when `wyr bench` prints numbers on ARM64 against targets in the wiki (subscribe p99 < 2 ms LAN, list 1000 < 50 ms, 50k samples/s < 50 % CPU on 4 cores).

## Conventions
- `cargo fmt`, `cargo clippy --workspace --all-targets -- -D warnings`, `cargo test --workspace` must pass.
- Pin `zenoh` to an exact version in `Cargo.toml`; upgrade quarterly with the fixture suite.
- Drivers: all I/O with timeouts, no `unwrap` on network paths, honest quality (`uncertain/stale` → `bad/comm_fail`), profiles declared before nodes.
- QoS: `~set/~act` → Priority InteractiveHigh + Block + express; `~val` → Data + Drop; `~meta` → DataHigh + Block.
- Never log secrets, `ptok`, or `~val` values above `trace`.
