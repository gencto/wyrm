# Contributing

- `spec/` is normative. Any change there: update `spec/fixtures/gen.py`, regenerate fixtures, make every SDK's compatibility test pass, add a line to `spec/CHANGELOG.md`.
- Unknown CBOR keys must be ignored by decoders; never remove or renumber a key.
- `cargo fmt`, `cargo clippy -D warnings`, `cargo test` before a PR.
- Architecture decisions go to `docs/adr/` (one file per decision).

## Wire enums (code tables)

Every code table in `spec/tables.json` (type, perm, writable, quality, status, …) has exactly one Rust declaration, made with `wyrm_core::wire_enum!`:

```rust
wyrm_core::wire_enum! {
    /// Value quality (spec 03-val, key 1).
    #[derive(Default)]
    pub enum Quality {
        #[default]
        Good = 0 => "good",
        Uncertain = 1 => "uncertain",
        Bad = 2 => "bad",
    }
}
```

Rules:
1. Each variant carries its wire code and its spec name, the same name as in `tables.json`. Do not hand-write `TryFrom<u8>` or a second match table.
2. Use typed values in all logic: `Perm`, `Quality`, `TypeCode`, … Convert to `u8` only at the codec edge, with `.code()` or `u8::from(x)`. Convert back only with `T::try_from(u8)`. No `as u8` outside the macro.
3. An unknown code in a decoder is an error for security-relevant fields (`Perm` in `ptok` and `maxperm`): the message is refused, never widened. Status codes are the exception: unknown values travel as `StatusCode::User`/`Unknown`, and code that needs to act on them uses `StatusGroup`.
4. Ranges with a meaning (status groups, user-defined status range) get a name (`StatusGroup`, `status::USER_RANGE`), never a bare `0x20` at a call site.
5. Adding or changing a code: change `spec/tables.json` first (normative), then the `wire_enum!` declaration. `wire_enums_match_spec_tables` in `crates/wyrm-core/tests/fixtures.rs` fails until both agree; a new table also gets a `check!` line there.
