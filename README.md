# WYRM

A broker with IOT-DSA semantics (node tree, reactive `list`/`subscribe`/`invoke`, managed connectors, data-flow) on top of [Eclipse Zenoh](https://zenoh.io) as transport and data fabric.

*Wyrm* — a wingless serpent-dragon: a long body of segments, like a tree of nodes; kin to the dragon on Zenoh's logo.

## Status
- **Iteration 1 (core)** — done. `modbus` and `mockdev` run on the driver framework (ADR 0004); the bench `mock` stays on the raw layer.
- **Iteration 2 (control plane)** — done: link registry, tokens, internal CA, generated ACL, supervisor, quarantine, audit, encrypted link secrets.
- **Iteration 3 (flow)** — engine in `wyrmd` (`wy/<site>/dataflows`); deploys prove the deployer's rights on every command target.
- **Iteration 4 (two brokers)** — `peers` over QUIC + mTLS; upstream sites command devices below, `sys` only where allowed (ADR 0018); optional `~val` downsampling.
- **Iteration 5 (security)** — user gateway (HTTP + WebSocket, roles → per-request `ptok`), responder rate limits, audit of every `set`/`invoke`.

| Crate | Purpose |
|---|---|
| `crates/wyrm-core` | wire types (`Value`, `Sample`, `NodeMeta`, `Attachment`, `Status`, `PtokClaims`), canonical CBOR codec, key-space helpers, `wire_enum!` |
| `crates/wyrm-link-sdk` | `trait Link`, `LinkCtx`, node tree, one queryable per link, `ptok` checks, liveliness, `TestHarness`, process host (`run::<L>()`) |
| `crates/wyrm-client` | `list` / `subscribe` as streams, `set`, `invoke`, `meta`, `resolve`, token sources |
| `crates/wyrm-state` | control-plane state: WAL (CBOR, CRC32C per record, HMAC chain) + postcard snapshot |
| `crates/wyrm-history` | embedded historian: watch groups (None / Interval / All Data / Point Change), redb store with one file per day, Get History with rollups (ADR 0014, [`docs/history.md`](docs/history.md)) |
| `crates/wyrm-storage` | broker storage `wy/<site>/storage` (as a DSA broker's `/data`): folders and typed values people create, `publish`, `export`/`import` as JSON, kept in one redb file (ADR 0017) |
| `crates/wyrm-admin` | registry, link tokens (argon2id), internal CA, generated ACL (links, operators, peer sites), supervisor, quarantine, audit, encrypted link secrets — the `wy/<site>/sys/**` tree |
| `crates/wyrm-flow` | data-flow engine: `~def` compiler, 15 node types, rhai sandbox, hot swap, node state in `wyrm-state` |
| `crates/wyrm-gateway` | user gateway: logins (argon2id), sessions, roles → grants, WebSocket CBOR proxy with per-point filtering |
| `crates/wyrmd` | broker: Zenoh router + static plugins (storage manager, REST) + admin + flow engine + gateway + links from `wyrmd.json5` |
| `links/mock` | N points × F Hz on a configurable tree (tests, benchmarks) |
| `links/probe` | test tool: runs scenarios through a broker's gateway as one of its users — actions, the `list` callbacks they cause (`added`/`changed`/`removed`, with delays) and values; built-ins `history`, `storage`, `tokens`, `dataflows`; as a link package (`Run Scenario`, secret `password`) or `wyr probe [names] --gateway http://127.0.0.1:8445 --site <site>` (password from `WYR_GATEWAY_PASSWORD`) |
| `crates/wyrm-gateway-client` | client of the user gateway (login, WebSocket CBOR requests and streams), plain HTTP on loopback |
| `links/modbus` | Modbus TCP on the driver framework (`connection → device → point`, DSA data types, batched FC1–4 reads, FC5/6/15/16/22 writes with read-back), with a simulator (`wyrm-modbus-sim`) |
| `links/mqtt` | MQTT on the driver framework: plain topics (raw or JSON pointer) and Sparkplug B (BIRTH/DATA/DEATH, NCMD/DCMD, rebirth); TLS (ring); password from the link secrets (`auth_ref`) |
| `crates/wyrm-wasm-host` | WebAssembly component host (no imports; fuel, memory and time limits) for the flow node `wasm` (ADR 0010) |
| `crates/wyrm-ffi` | C ABI over `wyrm-client` (`include/wyrm.h`) for Dart and other languages |
| `dart/` | `wyrm_core` (CBOR codec, 26 fixtures), `wyrm_client` (gateway WebSocket), `wyrm_ffi` (direct, via `wyrm-ffi`), `wyrm_flutter` (tree widget + example app) |
| `links/agent` | AI agent as a link: `~act/ask` plans with an LLM over read-only tools, `tasks/<id>` (`~state` restricted), human `approve` with per-key tokens; scoped service token, `allowed_prefixes`, daily token budget |
| `tools/wyrm-mcp` | MCP server over the tree for AI tools: browse, read, dry-run first, human approval for config-level changes (`docs/mcp.md`, ADR 0005) |
| `tools/wyr` | CLI: `list`, `meta`, `resolve`, `sub`/`watch`, `tree`, `set`, `invoke`, `values` (recorded history), `bench`, `keygen`, `token` (human approval), `admin …`, `flow …`, and dev commands `new link\|flow`, `dev`, `sim`, `record`, `replay` (`tools/wyr/README.md`) |

Planned: more links, `~val?history=` (spec 01/03) and a history view in the explorer.

## Quick start
`examples/wyrmd.json5` uses the current config format:
```json5
{
  site: "local",
  profile: "prod",                 // prod: loopback = requester only; dev: loopback = full rights
  data_dir: "./data",              // state, audit, CA, link certificates and tokens
  listen: ["tcp/127.0.0.1:7447", "tls/127.0.0.1:7448"],   // tls/ = process links and devices (mTLS)
  admin_keys: [],                  // public key from `wyr keygen`
  links: {
    mock: { driver: "mock", params: { points: 100, rate_hz: 1, depth: 2, fanout: 4 } },
    modbus: { driver: "modbus", mode: "process", params: { connections: { line1: { host: "127.0.0.1", port: 5020, devices: { ahu1: { unit: 1, points: { /* … */ } } } } } } },
  },
}
```
```
cargo build --release -p wyrmd -p wyr
target/release/wyr keygen --out admin.key          # prints the public key
# put that key into admin_keys in examples/wyrmd.json5, then:
cargo run -p wyrm-link-modbus --features bin --bin wyrm-modbus-sim &   # for the modbus link
target/release/wyrmd -c examples/wyrmd.json5
target/release/wyr list wy/local/downstream
target/release/wyr list --watch wy/local/downstream/mock/g0
target/release/wyr sub 'wy/local/downstream/mock/**'
target/release/wyr --key admin.key set wy/local/downstream/mock/g0/g0/p0 42
target/release/wyr --key admin.key invoke wy/local/downstream/mock count n=3
target/release/wyr bench list wy/local/downstream/mock
```
`mode: "process"` runs the driver as a child process (`wyrmd link <driver>`) that connects over loopback mTLS with its own certificate.

## Control plane
`wyrm-admin` serves `wy/<site>/sys/**` with the same `list`/`subscribe`/`invoke` as devices. Actions need a `ptok` with `config`, except `hello`, which checks the link token.

| Node | Actions / value |
|---|---|
| `sys` | values as on a DSA broker (versions, start time, traffic per second, `allow_all_links`, `enable_quarantine`); `~act/clear_conns`, `get_permissions`, `update_permissions {role, path, level}` |
| `sys/links` | Install Link ▸ `~act/install {id, driver, mode, params}` (from Driver), `install_zip {name, zip}`, `install_url {name, url}`, `install_git {name, url, ref}`, `install_repo {name, package}`, `install_wasm {name, wasm}` — packages run as process or WASM links; see [`docs/links.md`](docs/links.md) |
| `sys/packages/<name>` | installed link package (version, kind, source, SHA-256); `~act/remove` |
| `sys/upstream` | brokers this one connects to (as DSA's): `~act/add {name, url, ca, token, enabled}` with `url` the upstream's `peers.enroll`; this broker makes its own key and asks for its certificate; `<site>` shows `url`, `ca`, `certificate`, `key` (SHA-256 of our public key), `status` (`pending authorization`, `issued`, a refusal), writable `enabled`; `~act/remove` (ADR 0015) |
| `sys/overlays/<link>` | attributes the broker lays over that link's nodes (ADR 0016): today `attr.history` of each recorded point (its watch keys); the link's SDK merges them into `~meta` and the `view=list` summary (`has_history`) |
| `sys/tokens` | `~act/add {count, hours}` → a token (shown once) that admits a downstream broker at once; `<id>` shows `uses` and `expires`, `~act/remove` |
| `sys/~act/enroll` | open action on the `peers.enroll` listener: a downstream broker's `{site, csr, token, via}` → `{status: issued, certificate, port}`, `pending` or `refused` |
| `sys/links/<id>` | `~act/start`, `stop`, `remove`, `hello {token}`, `set_secret {name, value}`, `delete_secret {name}`, `update {params}`, `history`, `rollback {rev}` (runtime-installed links; the last 10 params revisions are kept), `grant {path, level}` (requester grants, ADR 0013); child `state` (`installed`, `starting`, `connected`, `stopping`, `stopped`, `failed`) |
| `sys/quarantine` | `~act/authorize {dsid, group, name, via}`, `deauthorize {link}` (a runtime external link or downstream broker goes back to quarantine) |
| `sys/quarantine/<cn>` | unknown CA-signed certificate (a link over `tls`, or a downstream broker `broker:<site>` over `quic`, `attr.kind`); `~act/approve {driver, params, group, name}` (`{via}` for a broker), `reject` |
| `sys/log_level`, `sys/~act/get_log {lines, level, filter, link}` | broker log level (saved) and its last log lines; `sys/links/<id>/log_level` and `~act/get_log` for each embedded or process link |
| `sys/acl_denied` | router access-control drops (with the other broker status values: uptime, links, sessions, CPU, memory, disk) |
| `sys/history` | embedded historian (ADR 0014): database values, `auto_purge`, `disk_space_remaining`, `retention_days`; `~act/add_watch_group {name, logging_type, interval, buffer_flush_time}`, `purge {timerange}`; `sys/history/<group>`: `edit`, `add_watch_path {path}`, `remove {purge}`; `sys/history/<group>/w<N>`: `enabled`, `start_date`, `end_date`, `get_history {timerange, interval, rollup, limit}`, `purge`, `unsubscribe`, `unsubscribe_purge` — see [`docs/history.md`](docs/history.md) |
| `sys/audit` | `~act/tail {n}` — HMAC-chained audit records |
| `wy/<site>/sys/broker` | liveliness token of the broker (no node); `sys` `~meta` carries `attr.proto`, `version`, `site` |

`wyr` gets admin commands as well (links, install, set-secret, …) — see `wyr --help`. ACL changes rebuild the router runtime (ADR 0006).

Link secrets (device passwords, keys) live in `data_dir/secrets.bin` (ChaCha20-Poly1305, key file 0600), never in the tree, `~def` or logs. `install` refuses params that look like secrets. Embedded links get them at start, process links in the `hello` reply; a link sees a new secret on its next start. `wyr admin set-secret <site> <id> <name>` reads the value from stdin.

## Profiles
A node's `~meta.is` names a profile; absent fields come from it, through `extends` (spec 02). The admin serves `wy/<site>/pub/<profile>/~meta` (10 built-ins such as `wy:number`, `wy:folder`, `wy:link`; others stored in its WAL) and changes them with `sys/profiles/~act/put {name, profile}` and `remove {name}` (`config`). `?expand=true` returns a profile with its chain folded in; `WyrmClient::meta_expanded(node)` returns a node's `~meta` with its profile applied. Links and upstream sites may read `pub/**`; nobody but the admin writes it.

## Storage
`wy/<site>/storage` keeps nodes and values people create, as a DSA broker's `/data` (ADR 0017). The root offers `add_node {name}`, `add_value {name, type, editor}`, `publish {path, value}` (creates the missing folders and a `dynamic` value), `export` and `import {data | file}` (JSON: `$type`, `@editor`, `?value`, children as objects, binary as `{"$hex": …}`; a `file` larger than a WebSocket frame goes over `POST /api/invoke`); a folder also offers `delete {recursive}`, `rename {name}` and `duplicate {name}`, a value `~set`, `delete`, `rename` and `duplicate`. Types: `string`, `number`, `bool`, `array`, `map`, `binary`, `dynamic`. Every action and `~set` needs `write`; the admin keys, users through the gateway (viewer `read`, operator `write`, engineer `config`) and flows (at `write`) are trusted. The tree lives in `data_dir/storage/storage.redb`: structure at once, values at most once a second. Limits: 10 000 nodes, 16 levels, 32 KiB per value, 64 MiB in all, 4 MiB per import or export. A link stored under the id `storage` (before spec 0.2.2) stops `wyrmd` from starting: remove it with the previous version. The historian may watch storage values (`add_watch_path {path: "storage/…"}`); an upstream site reads them.

## Flows
The explorer edits flows (ADR 0019): **Edit Dataflow** on a flow, **New Dataflow** on `dataflows`. A window shows the node types (`dataflows/~act/node_types`) on the left, the blocks with a row per port and their wires in the middle, and the selected block's (or the flow's) properties on the right. Drag a type onto the canvas, drag from an output pin to an input pin to link, double-click an input pin to unlink, drag a block by its header; each edit is checked (`validate`), **Deploy** sends a new version with the blocks' positions (`~def.layout`).

Besides `expression`, `window`, `alarm` and the other node types, a flow has logic blocks (`number`, `add`, `round`, `modulo`, `if`, `hub`, `stopwatch`, `concat`, …; ADR 0032): see [docs/flow-blocks.md](docs/flow-blocks.md).

`wy/<site>/dataflows/~act/deploy {def, proofs}` deploys a flow (spec 06); `~def` is read-only. Links trust the flow engine's key, so the deployer sends one token per command target (`proofs`: target key → token with at least the flow's `maxperm`, same subject). Targets must be exact keys under `wy/<site>/downstream/` or `wy/<site>/storage/`. `wyrm_flow::command_targets` and `WyrmClient::proof` build the proofs.
```
wyr --key admin.key flow validate local peak.json5     # compile only
wyr --key admin.key flow deploy   local peak.json5     # signs one proof per invoke/set target
wyr flow list local                                     # id, state (running|stopped|error), version
wyr --key admin.key flow show local peak                # state + ~def
wyr --key admin.key flow stop|start|reload|remove local peak
```

## Two brokers
```json5
// central: brokers connect on 7449; they ask for their certificate on 7450
peers: { listen: "quic/0.0.0.0:7449", enroll: "quic/0.0.0.0:7450" },
```
As in DSA (ADR 0015), the downstream broker adds the connection itself: on edge, `sys/upstream` ▸ **Add Upstream Connection** {Name `central`, Url `quic/central.example:7450`, CA (central's `data_dir/pki/ca.pem`), Token (optional)}. Edge makes its own key and asks central for a certificate. Central admits it:
1. at once with a token from its `sys/tokens` ▸ Add Token, when edge relays no sites;
2. at once with `sys/allow_all_links` on, when edge relays no sites;
3. else edge waits in `sys/quarantine/edge` (`kind: broker`): compare its `key` with edge's `sys/upstream/central/key`, then **Authorize** (Via: the sites edge relays).

A broker that names relayed sites (`via`, at most 16) always waits for Authorize, token or not: only an administrator gives a downstream broker the right to publish under other sites' names (security review ADM-2, ADR 0031).

Edge then connects on 7449 and shows up in `wy/central/downstream/edge`; **Deauthorize** sends it back to quarantine. Central's QUIC listeners trust its own CA alone (certificate CN `broker:<site>`); edge trusts central's CA only on that connection.

Without runtime steps (`wyrmd.json5` on both sides): central lists `downstream: [{ site: "edge" }]` and `wyrmd -c central.json5 ca` issues `data_dir/peers/edge/broker.{pem,key}`; edge names them: `upstream: [{ site: "central", endpoint: "quic/central.example:7449", ca, cert, key }]`. The upstream site may subscribe and query `~meta|~val` under `wy/<edge>/{downstream,dataflows,sys,upstream,storage}/**` (and `~def|~state` under `downstream`/`dataflows`). Requesters at the central broker may read `wy/<edge>/**`.

Commands from above (ADR 0018): central's users (through its gateway) and operators (with central's admin key, `SigningTokens::new(key, "edge")`) may `set` and `invoke` on edge's `downstream`, `dataflows` and `storage` at `write`, as far as their grants at central go (`wy/central/x` grants count as `wy/edge/x`); `config` there (link actions such as Export, Edit, Stop) and edge's `sys` only when edge allows it: `allow_config: true` on the `peers.upstream` entry, or `sys/upstream/central/allow_config`. Edge learns the keys that sign these requests from `wy/central/sys/signing_keys` (central's admin keys and gateway key, and the keys above central; for `config` only those every hop allows) and trusts them only within its own site, at those levels; learning new keys rebuilds edge once. A `sys` action that edge does not allow is dropped on the way, so the caller sees a timeout. Edge's audit names the user as `user:<name>@central`. Clocks must agree within a few minutes (tokens live 5 minutes).

Certificates last 365 days. The broker issues its own again (listener, client, process links, `data_dir/peers/<d>/broker.*`) when one has less than 30 days left: at a start, at each rebuild and in an hourly check that rebuilds when one was renewed. A downstream broker that enrolled asks its upstream again with the same key in those 30 days, and the upstream signs a new certificate for that key (audit `renew`); if the upstream does not renew, `sys/upstream/<u>/status` says so and the downstream asks again every hour (security review D-1, ADR 0031). УВАГА: files issued for `peers.downstream` without enrollment (`wyrmd ca`) are renewed only in the upstream's `data_dir/peers/<d>/`: copy them to the downstream again before the old ones end.

A chain `plant → edge → central`: edge lists plant as its downstream (and listens on QUIC), central adds `via: ["plant"]` to its edge entry, and then reads `wy/plant/**` through edge (ADR 0007) and commands it as plant allows (`allow_config` at each hop for `sys`).

Demo with a chain of three sites, connectors and the Flutter app:
`examples/demo/run.sh` starts `central`, `edge` (`mock`, `mockdev`, `modbus`
as a process link, `modbus_slave`, `http`, `snmp`, `prometheus`) and `plant`
(`mock`, `s7`, `bacnet`, `opcua`; connected to edge), each link against its
simulator, each with a gateway (`:8445`, `:8444`, `:8446`, user
`admin`, password `wyrm-demo-1`); central reads plant through edge. `wyrmd -c <cfg> ca` creates a site's CA
and the certificates of the sites below it before they start. App: `cd dart/wyrm_flutter/example &&
flutter create --platforms=macos . && flutter run -d macos` (raise
`MACOSX_DEPLOYMENT_TARGET` to 12.0 and add the `network.client`
entitlement); root `wy/edge/downstream`, the tune icon opens a node's `~meta`
and actions.

## Gateway
```json5
gateway: { listen: "0.0.0.0:8443", tls_cert: "gw.pem", tls_key: "gw.key", admin_user: "admin" },
```
Start `wyrmd` once with `WYRM_GATEWAY_ADMIN_PASSWORD` set to create the first admin. On a stopped broker, `wyrmd -c wyrmd.json5 user list|add <name> --roles a,b|passwd|roles|disable|enable|remove` manages users (passwords from stdin, changes audited as `local:cli`); while it runs, the stores are locked and the gateway's `/api/users` endpoints do the same. `POST /api/login {user, password}` (CBOR) returns a session; `POST /api/ws-ticket` (bearer session) returns a single-use 30 s ticket, and `GET /api/ws?ticket=…` opens the WebSocket proxy (`list`, `subscribe`, `set`, `invoke`, filtered by the user's grants). The gateway signs one `ptok` per request with its own key, which links, the flow engine and the admin (`sys/**`) trust; the user's grants decide what each request may do, and only the `admin` role has grants on `sys/**` (ADR 0009). Whoever can read `data_dir/gateway/gateway.key` is therefore a full administrator: keep `data_dir` readable by the broker user only. One user holds at most 8 WebSockets and sends at most 100 requests per second over all of them (burst 200; `rate_limited` past it); a `history` request asks for at most 10 000 rows (security review GW-2).

## Spec and fixtures
`spec/fixtures/fixtures.json` holds 23 canonical CBOR samples. Every SDK (Rust, Dart, C) must decode each to the documented JSON and re-encode to the exact bytes. Regenerate with `python spec/fixtures/gen.py`; CI fails if fixtures drift.

## Build
```
cargo fmt --all --check
cargo clippy --workspace --all-targets --all-features -- -D warnings
cargo test --workspace --all-features
```

## License
Apache-2.0
