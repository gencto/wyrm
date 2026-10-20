# WYRM

A broker with IOT-DSA semantics (node tree, reactive `list`/`subscribe`/`invoke`, managed connectors, data-flow) on top of [Eclipse Zenoh](https://zenoh.io) as transport and data fabric.

*Wyrm* — a wingless serpent-dragon: a long body of segments, like a tree of nodes; kin to the dragon on Zenoh's logo.

## Status
Iteration 0 — specification and wire codec. See `spec/` (normative) and `crates/wyrm-core`.

| Crate | Purpose |
|---|---|
| `wyrm-core` | wire types (`Value`, `Sample`, `NodeMeta`, `Attachment`, `Status`), canonical CBOR codec, key-space helpers |

Planned: `wyrm-link-sdk`, `wyrm-client`, `wyrm-state`, `wyrm-history`, `wyrm-flow`, `wyrm-admin`, `wyrmd`, `links/*`, `tools/wyr`.

## Spec and fixtures
`spec/fixtures/fixtures.json` holds 22 canonical CBOR samples. Every SDK (Rust, Dart, C) must decode each to the documented JSON and re-encode to the exact bytes. Regenerate with `python spec/fixtures/gen.py`; CI fails if fixtures drift.

## Build
```
cargo test --workspace
```

## License
Apache-2.0
