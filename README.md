# WYRM

A broker with IOT-DSA semantics (node tree, reactive `list`/`subscribe`/`invoke`, managed connectors, data-flow) on top of [Eclipse Zenoh](https://zenoh.io) as transport and data fabric.

*Wyrm* — a wingless serpent-dragon: a long body of segments, like a tree of nodes; kin to the dragon on Zenoh's logo.

## Status
- **Iteration 1 (core)** — done on the SDK raw layer. Porting `mock` and `modbus` onto the driver framework (ADR 0004) is pending.
- **Iteration 2 (control plane)** — in progress: link registry, tokens, internal CA, generated ACL, supervisor, quarantine, audit.

| Crate | Purpose |
|---|---|
| `crates/wyrm-core` | wire types (`Value`, `Sample`, `NodeMeta`, `Attachment`, `Status`, `PtokClaims`), canonical CBOR codec, key-space helpers, `wire_enum!` |
| `crates/wyrm-link-sdk` | `trait Link`, `LinkCtx`, node tree, one queryable per link, `ptok` checks, liveliness, `TestHarness`, process host (`run::<L>()`) |
| `crates/wyrm-client` | `list` / `subscribe` as streams, `set`, `invoke`, `meta`, `resolve`, token sources |
| `crates/wyrm-state` | control-plane state: WAL (CBOR, CRC32C per record, HMAC chain) + postcard snapshot |
| `crates/wyrm-admin` | registry, link tokens (argon2id), internal CA, generated ACL, supervisor, quarantine, audit — the `wy/<site>/sys/**` tree |
| `crates/wyrmd` | broker: Zenoh router + static plugins (storage manager, REST) + admin + links from `wyrmd.json5` |
| `links/mock` | N points × F Hz on a configurable tree (tests, benchmarks) |
| `links/modbus` | Modbus TCP on `tokio-modbus`, with a simulator (`wyrm-modbus-sim`) |
| `tools/wyr` | CLI: `list`, `meta`, `resolve`, `sub`, `set`, `invoke`, `bench`, `keygen` |

Planned: `wyrm-history`, `wyrm-flow`, `wyrm-mcp`, more links.

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
    plc1: { driver: "modbus", mode: "process", params: { host: "127.0.0.1", port: 5020, points: [ /* … */ ] } },
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
| `sys/links/<id>` | `~act/start`, `stop`, `remove`, `hello {token}`; child `state` (`installed`, `starting`, `connected`, `stopping`, `stopped`, `failed`) |
| `sys/quarantine/<cn>` | unknown CA-signed certificate; `~act/approve {driver, params}`, `reject` |
| `sys/metrics/broker/acl_denied_total` | router access-control drops |
| `sys/audit` | `~act/tail {n}` — HMAC-chained audit records |
| `sys/broker` | liveliness of the broker |

`wyr` gets admin commands as well (links, install, …) — see `wyr --help`. ACL changes rebuild the router runtime (ADR 0006).

## Spec and fixtures
`spec/fixtures/fixtures.json` holds 22 canonical CBOR samples. Every SDK (Rust, Dart, C) must decode each to the documented JSON and re-encode to the exact bytes. Regenerate with `python spec/fixtures/gen.py`; CI fails if fixtures drift.

## Build
```
cargo fmt --all --check
cargo clippy --workspace --all-targets --all-features -- -D warnings
cargo test --workspace --all-features
```

## License
Apache-2.0
