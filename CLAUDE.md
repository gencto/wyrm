# WYRM — project context for Claude Code

Broker with IOT-DSA semantics (node tree, reactive list/subscribe/invoke, managed connectors, data-flow) on top of Eclipse Zenoh 1.x as transport. One Rust binary `wyrmd` = Zenoh runtime (router) + static plugins. Zenoh is never patched or forked.

## Language and docs
- Code, comments, commit messages: English. Design wiki (Obsidian, outside this repo at `~/Documents/Obsidian/Wiki/Zenoh`) and discussions with the owner: Ukrainian.
- `spec/` is **normative**. Any change there → update `spec/fixtures/gen.py` → regenerate → every SDK's fixture test must pass → line in `spec/CHANGELOG.md`.
- Decisions go to `docs/adr/NNNN-*.md`. Read ADR 0001–0003 before touching architecture.

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
tools/wyr               CLI
```

## Current state
Iteration 0 done (2026-10-20): spec v0.1, `wyrm-core`, 22 fixtures green, CI config in `docs/ci.yml.pending` (move to `.github/workflows/ci.yml`).

## Next: Iteration 1 — core (in this order)
1. `wyrm-link-sdk`: `trait Link { start, reconfigure, on_set, on_invoke, stop }`, `LinkCtx { declare_node, declare_action, update, publisher, remove_node, set_dynamic, mark_all, client, secrets, metrics }`; SDK declares ONE queryable on `wy/<site>/down/<link>/**`, routes by suffix, answers `~meta?view=list|keys|full`, checks `ptok` before calling the driver, sets liveliness; `TestHarness` with in-memory Zenoh runtime (`zenoh::Config` mode peer, no network).
2. `links/mock`: N points × F Hz, configurable tree depth — needed for every later test and for `wyr bench`.
3. `wyrm-client`: `list()` = subscribe `*/~meta` + liveliness `*` BEFORE `get ~meta?view=list` (no lost-update window), emit `Refreshed/Added/Changed/Removed/Disconnected`; `subscribe()` = `get ~val` (storage) + subscribe; `set/invoke` = `get` with payload + attachment.
4. `wyrmd` minimal: config → `zenoh::Config` built programmatically, router mode, storage-manager (`mem` on `**/~val`, `rocksdb` on `{flows,pub,sys}/**`), embedded `mock`. No admin/flow/TLS yet.
5. `tools/wyr`: `list`, `sub`, `set`, `invoke`, `bench` (p50/p95/p99 on subscribe and list-1000).
6. `links/modbus` on `tokio-modbus`, verified against `diagslave`.

Done when `wyr bench` prints numbers on ARM64 against targets in the wiki (subscribe p99 < 2 ms LAN, list 1000 < 50 ms, 50k samples/s < 50 % CPU on 4 cores).

## Conventions
- `cargo fmt`, `cargo clippy --workspace --all-targets -- -D warnings`, `cargo test --workspace` must pass.
- Pin `zenoh` to an exact version in `Cargo.toml`; upgrade quarterly with the fixture suite.
- Drivers: all I/O with timeouts, no `unwrap` on network paths, honest quality (`uncertain/stale` → `bad/comm_fail`), profiles declared before nodes.
- QoS: `~set/~act` → Priority InteractiveHigh + Block + express; `~val` → Data + Drop; `~meta` → DataHigh + Block.
- Never log secrets, `ptok`, or `~val` values above `trace`.
