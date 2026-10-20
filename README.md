# WYRM

A broker with IOT-DSA semantics (node tree, reactive `list`/`subscribe`/`invoke`, managed connectors, data-flow) on top of [Eclipse Zenoh](https://zenoh.io) as transport and data fabric.

*Wyrm* — a wingless serpent-dragon: a long body of segments, like a tree of nodes; kin to the dragon on Zenoh's logo.

## Status
Iteration 1 — core: one broker binary, the connector SDK, a requester SDK, a CLI, and two connectors.

| Crate | Purpose |
|---|---|
| `crates/wyrm-core` | wire types (`Value`, `Sample`, `NodeMeta`, `Attachment`, `Status`, `PtokClaims`), canonical CBOR codec, key-space helpers, `wire_enum!` |
| `crates/wyrm-link-sdk` | `trait Link`, `LinkCtx`, node tree, one queryable per link, `ptok` checks, liveliness, `TestHarness` |
| `crates/wyrm-client` | `list` / `subscribe` as streams, `set`, `invoke`, `meta`, `resolve`, token sources |
| `crates/wyrmd` | broker: Zenoh router + storage manager (static plugin) + embedded links from `wyrmd.json5` |
| `links/mock` | N points × F Hz on a configurable tree (tests, benchmarks) |
| `links/modbus` | Modbus TCP on `tokio-modbus`, with a simulator (`wyrm-modbus-sim`) |
| `tools/wyr` | CLI: `list`, `meta`, `resolve`, `sub`, `set`, `invoke`, `bench`, `keygen` |

Planned: `wyrm-state`, `wyrm-history`, `wyrm-flow`, `wyrm-admin`, more links.

## Quick start
```
cargo build --release -p wyrmd -p wyr
target/release/wyr keygen --out admin.key          # prints the public key
# put that key into admin_keys in examples/wyrmd.json5, then:
target/release/wyrmd -c examples/wyrmd.json5
target/release/wyr list wy/local/down
target/release/wyr list --watch wy/local/down/mock/g0
target/release/wyr sub 'wy/local/down/mock/**'
target/release/wyr --key admin.key set wy/local/down/mock/g0/g0/p0 42
target/release/wyr --key admin.key invoke wy/local/down/mock count n=3
target/release/wyr bench list wy/local/down/mock
```
For the Modbus link in the example, start the simulator first:
`cargo run -p wyrm-link-modbus --features bin --bin wyrm-modbus-sim`.

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
