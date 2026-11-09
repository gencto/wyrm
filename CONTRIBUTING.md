# Contributing

- `spec/` is normative. Any change there: update `spec/fixtures/gen.py`, regenerate fixtures, make every SDK's compatibility test pass, add a line to `spec/CHANGELOG.md`.
- Unknown CBOR keys must be ignored by decoders; never remove or renumber a key.
- `cargo fmt`, `cargo clippy -D warnings`, `cargo test` before a PR.
- Architecture decisions go to `docs/adr/` (one file per decision).
- Tests: a Zenoh subscriber that the test does not read at once (it waits for something else first) uses `zenoh::handlers::RingChannel` or a callback, not the default FIFO. A full FIFO (256 samples) blocks the session's receive path, so every other query and subscriber on that session stops too (the `broker_restart_rto` flake, 2026-11-09). Product code follows the same rule; see "Streams and a slow consumer" below.

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

## Zenoh handlers (product code and tests)

The default Zenoh handler is a FIFO of 256 items. When it is full, Zenoh waits for room on the session's receive path, so every other reply and sample of that session stops too (`zenoh/src/api/handlers/fifo.rs`). One slow consumer then freezes the whole session; for the gateway that is every user at once.

Rules:
1. Use the default FIFO (or `FifoChannel`) only for replies or samples that the same task reads at once, with no other await in between: a one-shot `get` read to its end, or the first reply of a `get` whose handler is then dropped.
2. A subscriber, liveliness subscriber or long `get` that is not read at once (it waits for another query first, it forwards with back-pressure, or its consumer is somebody else) uses a callback into a bounded buffer that the code owns, or `zenoh::handlers::RingChannel`. In `wyrm-client` that is `intake::Intake` with a `Feed`.
3. A callback never awaits, blocks or does I/O: one short `std::sync::Mutex` section or a `try_send`.
4. A full buffer follows a policy chosen for its stream kind, written down next to it and in `docs/links.md` ("Streams and a slow consumer"): values (`~val`) keep the newest per key; queues (QoS 2/3) drop the oldest; `~meta` lists discard the buffer and read a fresh snapshot; action results end the stream with `resource_exhausted`. Each loss is counted (`EventStream::dropped`). Every buffer has a bound in items and, where it is keyed, in keys (`MAX_PENDING_KEYS`, `MAX_STREAM_KEYS`); a policy that reads again (a fresh snapshot) is bounded in rounds too (`MAX_RESYNCS`) and then ends the stream with `resource_exhausted`, never loops; filter what the consumer may not see before it is buffered, not after.
5. A buffer lives only as long as its reader: the handler holds it weakly (`Feed` holds a `Weak<Intake>`), and a long `get` gets a `CancellationToken` that is cancelled when the stream ends.
6. A test for a stream that can stall uses two sessions over loopback TCP (`crates/wyrm-client/tests/stall.rs`): in one session a local put calls the subscriber on the publisher's own task, and the stall does not show.
