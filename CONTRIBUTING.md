# Contributing

- `spec/` is normative. Any change there: update `spec/fixtures/gen.py`, regenerate fixtures, make every SDK's compatibility test pass, add a line to `spec/CHANGELOG.md`.
- Unknown CBOR keys must be ignored by decoders; never remove or renumber a key.
- `cargo fmt`, `cargo clippy -D warnings`, `cargo test` before a PR.
- Architecture decisions go to `docs/adr/` (one file per decision).
