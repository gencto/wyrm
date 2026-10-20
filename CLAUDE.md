# WYRM — project context for Claude Code

Broker with IOT-DSA semantics (node tree, reactive list/subscribe/invoke, managed connectors, data-flow) on top of Eclipse Zenoh 1.x as transport. One Rust binary `wyrmd` = Zenoh runtime (router) + static plugins. Zenoh is never patched or forked.

## Language and docs
- Code, comments, commit messages: English. Design wiki (Obsidian, outside this repo at `~/Documents/Obsidian/Wiki/Zenoh`) and discussions with the owner: Ukrainian.
- `spec/` is **normative**. Any change there → update `spec/fixtures/gen.py` → regenerate → every SDK's fixture test must pass → line in `spec/CHANGELOG.md`.
- Decisions go to `docs/adr/NNNN-*.md`. Read ADR 0001–0010 before touching architecture; ADR 0004 (driver framework) is mandatory reading before writing any `links/*`.

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
crates/wyrm-link-sdk    ✅ trait Link, LinkCtx, NodeTree, one queryable per link, liveliness, TestHarness
crates/wyrm-client      ✅ list()/subscribe()/set()/invoke() as Streams
crates/wyrm-state       ✅ WAL (CBOR, HMAC-chain, CRC/record) + postcard snapshot
crates/wyrm-history     trait HistoryStore + host; history/{rocksdb,influxdb}
crates/wyrm-flow        ✅ engine: compiler, node registry, rhai, runtime (deploy proofs per target)
crates/wyrm-admin       ✅ registry, supervisor, tokens, CA, quarantine, ACL generator (links, operators, peers), audit, SecretStore
crates/wyrm-gateway     ✅ user gateway: logins, sessions, roles → per-request ptok, WebSocket CBOR proxy
crates/wyrm-ffi         ✅ C ABI over wyrm-client (include/wyrm.h), events as gateway-style CBOR frames
dart/                   ✅ wyrm_core (fixtures), wyrm_client (gateway WS), wyrm_ffi, wyrm_flutter (WyrmTree)
tools/wyrm-mcp          ✅ MCP server over the tree (dry-run first, human approval tokens for config)
links/agent             ✅ AI agent link: ask → plan (LLM, read-only tools) → approve with human tokens → run
crates/wyrm-wasm-host   ✅ wasmtime component host: WIT wyrm:flow/node + wyrm:link/point, no imports, fuel/memory/time limits (ADR 0010)
crates/wyrmd            ✅ binary (router, storage + rest plugins, admin, flow engine, gateway, peers over QUIC, links; rebuild on ACL change)
links/{mock,modbus,mqtt,opcua,bacnet,dlms}   lib + bin (feature "bin"); modbus and mockdev on the driver framework, bench mock on the raw layer
tools/wyr               ✅ CLI ops part (dev commands: iteration 9)
tools/wyrm-mcp          MCP server over wyrm-client (ADR 0005)
links/agent             AI agent connector with approval workflow (ADR 0005)
```

## Current state
Iteration 0 done (2026-10-20): spec v0.1 (now 0.1.2), `wyrm-core`, 23 fixtures green. CI in `.github/workflows/ci.yml`.
Iteration 1 (2026-10-20): raw-layer steps 1, 2–6 done plus wiki items `rest` plugin (profile `dev` and loopback only: it runs inside the router, so the ACL does not see it) and Advanced Pub/Sub (zenoh-ext 1.10.1: `cfg.qos >= 2` → AdvancedPublisher cache, `subscribe_reliable`, feature `advanced`). Open: step 1b driver framework (ADR 0004) and porting `mock`/`modbus` onto it. Measured on Apple M4 Max (ARM64), loopback, release: list of 1000 children p99 0.57 ms; 50k samples/s at ~17 % of one core; one-point subscribe p99 1.2 ms under 50k/s. Missing: LAN run on the reference board (4-core ARM64, 2 GB).
Iteration 1 step 1b done: driver framework (ADR 0004) with `#[derive(Params)]`; `links/modbus` (FC1–4 batched reads, FC5/6/15/16/22 + RMW, probe/FC17 ping, simulator) and `mockdev` run on it.
Iteration 2 done: `wyrm-state`, `wyrm-admin` (registry, argon2id link tokens, rcgen CA, generated ACL, supervisor, quarantine via link events, `acl_denied_total` from router metrics, audit, `SecretStore` in `secrets.bin` with `set_secret`/`delete_secret`), `wyrmd link <driver>` process mode; all three wiki criteria pass in `crates/wyrmd/tests/e2e.rs`. Zenoh 1.10 has no live ACL reload, so ACL changes rebuild the router runtime (ADR 0006, proposed; peers ADR 0007, flow proofs ADR 0008, gateway trust ADR 0009).
Iteration 3: `wyrm-flow` runs in `wyrmd` at `wy/<site>/flows`. `~def` is read-only; `~act/deploy {def, proofs}` needs one admin-signed token per command target (≥ `maxperm`, same subject), targets only under `wy/<site>/down/`. Links trust the flow key (`ControlConfig.link_keys`); the admin and the engine do not.
Iteration 4: `peers` in `wyrmd.json5` — QUIC listener for downstream sites (their CAs only, per-endpoint `root_ca_certificate_file`), upstream connects with that site's CA, CN `broker:<site>`; upstream read-only in the ACL (no `~set`/`~act` queries); `upstream_val_hz` egress downsampling. e2e `two_brokers_over_quic`.
Iteration 9 (first version): `wyrm-mcp`, `wyr` dev commands (`new`, `dev`, `sim`, `record`, `replay`, `token`), Claude Code skills, `links/agent` (device models as `<vendor>:<model>` profiles, not `pub/models/**`). `wyrmd` hosts the `agent` driver; its signing key is a link secret created by the admin, and links trust it (and the flow key) only up to `write` (`LinkConfig.limited_keys`, `hello` → `limited_keys`). Not yet: cloud profile (OIDC, ClickHouse, Postgres), `llm` flow node.
Iteration 7 (first version): Dart packages and the Flutter tree widget work through the gateway (WS) and directly (FFI, loopback TCP only — no TLS yet); CI runs the Dart fixture test.
Iteration 8 (first version): `wyrm-wasm-host` and the flow node `wasm` (`put_artifact`, content-addressed artifacts, hot load by deploy). Profiles (`pub/**`, spec 0.1.2) served by the admin, inherited in the SDK (`expand=true`, `has_override`).
Iteration 5 (in progress): `wyrm-gateway` hosted by `wyrmd` (`gateway` section, first admin from `WYRM_GATEWAY_ADMIN_PASSWORD`, its key is trusted by links and the flow engine, not by the admin; link processes get a cleared environment); responder rate limits (verified subjects and unverified callers in separate limiters) and audit of every `set`/`invoke` (`sys/audit/<link>`, args as SHA-256).
Zenoh ≥ 1.10 facts: reply QoS follows the query (requester sets `~set/~act` QoS); default `get` consolidation drops stream replies (use `ConsolidationMode::None`); `Parameters` split on `;` — spec 01 uses `&`, so the SDK parses the raw selector string (verified through a router hop); the storage manager loads only `memory` statically — the rocksdb volume exists only as a dynamic `.so`.
Open owner decisions: (1) selector separator in spec 01; (2) ADR for requester-side QoS; (3) single-use `jti` reading of spec 04; (4) persistence of `{flows,pub,sys}/**`: rocksdb volume (needs a `.so`, conflicts with principle 2) vs `wyrm-state` WAL (ADR 0003) — step 4 runs `mem` on `~val` only; (5) `diagslave` check of `links/modbus` (tests use the built-in simulator); (6) "polling only while subscribed" is defeated by the `wy/**/~val` storage subscription, and process links never see subscriptions through the ACL (`poll_unsubscribed: true` workaround); (7) the control plane is not reachable through the gateway (the admin does not trust its key); (8) flow `invoke`/`set` sinks cannot reach other sites or `sys/**`. `wyrmd` refuses plaintext non-loopback endpoints unless `insecure_plaintext: true` (until TLS).

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
- Code tables (`tables.json`) are declared once with `wyrm_core::wire_enum!`; logic uses the typed enum, `u8` only at the codec edge via `.code()` / `try_from`. No `as u8`, no hand-written `TryFrom<u8>`, no bare range numbers (use `StatusGroup`). Details: `CONTRIBUTING.md` → Wire enums.
