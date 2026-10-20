# WYRM

A broker with IOT-DSA semantics (node tree, reactive `list`/`subscribe`/`invoke`, managed connectors, data-flow) on top of [Eclipse Zenoh](https://zenoh.io) as transport and data fabric.

*Wyrm* — a wingless serpent-dragon: a long body of segments, like a tree of nodes; kin to the dragon on Zenoh's logo.

## Status
- **Iteration 1 (core)** — done. `modbus` and `mockdev` run on the driver framework (ADR 0004); the bench `mock` stays on the raw layer.
- **Iteration 2 (control plane)** — done: link registry, tokens, internal CA, generated ACL, supervisor, quarantine, audit, encrypted link secrets.
- **Iteration 3 (flow)** — engine in `wyrmd` (`wy/<site>/flows`); deploys prove the deployer's rights on every command target.
- **Iteration 4 (two brokers)** — `peers` over QUIC + mTLS; upstream sites read only; optional `~val` downsampling.
- **Iteration 5 (security)** — user gateway (HTTP + WebSocket, roles → per-request `ptok`), responder rate limits, audit of every `set`/`invoke`.

| Crate | Purpose |
|---|---|
| `crates/wyrm-core` | wire types (`Value`, `Sample`, `NodeMeta`, `Attachment`, `Status`, `PtokClaims`), canonical CBOR codec, key-space helpers, `wire_enum!` |
| `crates/wyrm-link-sdk` | `trait Link`, `LinkCtx`, node tree, one queryable per link, `ptok` checks, liveliness, `TestHarness`, process host (`run::<L>()`) |
| `crates/wyrm-client` | `list` / `subscribe` as streams, `set`, `invoke`, `meta`, `resolve`, token sources |
| `crates/wyrm-state` | control-plane state: WAL (CBOR, CRC32C per record, HMAC chain) + postcard snapshot |
| `crates/wyrm-admin` | registry, link tokens (argon2id), internal CA, generated ACL (links, operators, peer sites), supervisor, quarantine, audit, encrypted link secrets — the `wy/<site>/sys/**` tree |
| `crates/wyrm-flow` | data-flow engine: `~def` compiler, 15 node types, rhai sandbox, hot swap, node state in `wyrm-state` |
| `crates/wyrm-gateway` | user gateway: logins (argon2id), sessions, roles → grants, WebSocket CBOR proxy with per-point filtering |
| `crates/wyrmd` | broker: Zenoh router + static plugins (storage manager, REST) + admin + flow engine + gateway + links from `wyrmd.json5` |
| `links/mock` | N points × F Hz on a configurable tree (tests, benchmarks) |
| `links/modbus` | Modbus TCP on the driver framework (`connection → device → point`, DSA data types, batched FC1–4 reads, FC5/6/15/16/22 writes with read-back), with a simulator (`wyrm-modbus-sim`) |
| `links/mqtt` | MQTT on the driver framework: plain topics (raw or JSON pointer) and Sparkplug B (BIRTH/DATA/DEATH, NCMD/DCMD, rebirth); TLS (ring); password from the link secrets (`auth_ref`) |
| `tools/wyr` | CLI: `list`, `meta`, `resolve`, `sub`, `set`, `invoke`, `bench`, `keygen`, `admin …` |

Planned: `wyrm-history`, `wyrm-mcp`, more links.

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
    plc1: { driver: "modbus", mode: "process", params: { connections: { line1: { host: "127.0.0.1", port: 5020, devices: { ahu1: { unit: 1, points: { /* … */ } } } } } } },
  },
}
```
```
cargo build --release -p wyrmd -p wyr
target/release/wyr keygen --out admin.key          # prints the public key
# put that key into admin_keys in examples/wyrmd.json5, then:
cargo run -p wyrm-link-modbus --features bin --bin wyrm-modbus-sim &   # for plc1
target/release/wyrmd -c examples/wyrmd.json5
target/release/wyr list wy/local/down
target/release/wyr list --watch wy/local/down/mock/g0
target/release/wyr sub 'wy/local/down/mock/**'
target/release/wyr --key admin.key set wy/local/down/mock/g0/g0/p0 42
target/release/wyr --key admin.key invoke wy/local/down/mock count n=3
target/release/wyr bench list wy/local/down/mock
```
`mode: "process"` runs the driver as a child process (`wyrmd link <driver>`) that connects over loopback mTLS with its own certificate.

## Control plane
`wyrm-admin` serves `wy/<site>/sys/**` with the same `list`/`subscribe`/`invoke` as devices. Actions need a `ptok` with `config`, except `hello`, which checks the link token.

| Node | Actions / value |
|---|---|
| `sys/links` | `~act/install {id, driver, mode, params}` |
| `sys/links/<id>` | `~act/start`, `stop`, `remove`, `hello {token}`, `set_secret {name, value}`, `delete_secret {name}`; child `state` (`installed`, `starting`, `connected`, `stopping`, `stopped`, `failed`) |
| `sys/quarantine/<cn>` | unknown CA-signed certificate; `~act/approve {driver, params}`, `reject` |
| `sys/metrics/broker/acl_denied_total` | router access-control drops |
| `sys/audit` | `~act/tail {n}` — HMAC-chained audit records |
| `sys/broker` | liveliness of the broker |

`wyr` gets admin commands as well (links, install, set-secret, …) — see `wyr --help`. ACL changes rebuild the router runtime (ADR 0006).

Link secrets (device passwords, keys) live in `data_dir/secrets.bin` (ChaCha20-Poly1305, key file 0600), never in the tree, `~def` or logs. `install` refuses params that look like secrets. Embedded links get them at start, process links in the `hello` reply; a link sees a new secret on its next start. `wyr admin set-secret <site> <id> <name>` reads the value from stdin.

## Profiles
A node's `~meta.is` names a profile; absent fields come from it, through `extends` (spec 02). The admin serves `wy/<site>/pub/<profile>/~meta` (10 built-ins such as `wy:number`, `wy:folder`, `wy:link`; others stored in its WAL) and changes them with `sys/profiles/~act/put {name, profile}` and `remove {name}` (`config`). `?expand=true` returns a profile with its chain folded in; `WyrmClient::meta_expanded(node)` returns a node's `~meta` with its profile applied. Links and upstream sites may read `pub/**`; nobody but the admin writes it.

## Flows
`wy/<site>/flows/~act/deploy {def, proofs}` deploys a flow (spec 06); `~def` is read-only. Links trust the flow engine's key, so the deployer sends one token per command target (`proofs`: target key → token with at least the flow's `maxperm`, same subject). Targets must be exact keys under `wy/<site>/down/`. `wyrm_flow::command_targets` and `WyrmClient::proof` build the proofs.
```
wyr --key admin.key flow validate local peak.json5     # compile only
wyr --key admin.key flow deploy   local peak.json5     # signs one proof per invoke/set target
wyr flow list local                                     # id, state (running|stopped|error), version
wyr --key admin.key flow show local peak                # state + ~def
wyr --key admin.key flow stop|start|reload|remove local peak
```

## Two brokers
```json5
// edge
peers: { upstream: [{ site: "central", endpoint: "quic/10.0.0.1:7449", ca: "central-ca.pem" }], upstream_val_hz: 1 },
// central
peers: { listen: "quic/0.0.0.0:7449", downstream: [{ site: "edge", ca: "edge-ca.pem" }] },
```
Each side trusts the other's CA only on the QUIC broker link (certificate CN `broker:<site>`). The upstream site may subscribe and query `~meta|~val|~def|~state` under `wy/<edge>/{down,flows}/**`, never `~set`/`~act`. Requesters at the central broker may read `wy/<edge>/**`.

## Gateway
```json5
gateway: { listen: "0.0.0.0:8443", tls_cert: "gw.pem", tls_key: "gw.key", admin_user: "admin" },
```
Start `wyrmd` once with `WYRM_GATEWAY_ADMIN_PASSWORD` set to create the first admin. On a stopped broker, `wyrmd -c wyrmd.json5 user list|add <name> --roles a,b|passwd|roles|disable|enable|remove` manages users (passwords from stdin, changes audited as `local:cli`); while it runs, the stores are locked and the gateway's `/api/users` endpoints do the same. `POST /api/login {user, password}` (CBOR) returns a session; `POST /api/ws-ticket` (bearer session) returns a single-use 30 s ticket, and `GET /api/ws?ticket=…` opens the WebSocket proxy (`list`, `subscribe`, `set`, `invoke`, filtered by the user's grants). The gateway signs one `ptok` per request with its own key, which links and the flow engine trust; the admin (`sys/**`) does not, so the control plane needs an operator key.

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
