---
name: wyrm-link
description: Create or extend a WYRM protocol connector (driver) on the driver framework of wyrm-link-sdk (ADR 0004) — a new crate under links/, Connection → Device → Point parameters with #[derive(Params)], impl Driver, a device simulator and TestHarness tests. Use when asked to add a link, driver or connector for a protocol or device (Modbus device model, BACnet, DLMS, a vendor TCP protocol, …) or to scaffold one with `wyr new link`.
---

# WYRM link (driver) on the driver framework

## Read first
1. `docs/adr/0004-driver-framework.md` — what the framework owns (tree, generated actions, edits, states, scheduling, polling (always by default, `poll_unsubscribed: false` gates on subscribers), read-back writes, quality ladder). Do not re-implement any of it in a driver.
2. `crates/wyrm-link-sdk/src/driver/mod.rs` — `trait Driver`, `DriverError`, `NodeState`.
3. Reference drivers: `links/modbus/src/lib.rs` (real protocol, batched plan, hand-written `Params` for cross-field rules) and `links/mock/src/df.rs` (`mockdev`, smallest complete driver). Tests to copy from: `links/modbus/tests/sim.rs`, `links/mock/tests/df.rs`.
4. `CLAUDE.md` conventions (QoS, secrets, no `unwrap` on network paths, `wire_enum!`).

## Steps
1. Scaffold — never write the crate by hand:
   ```
   cargo run -p wyr -- new link <name> --proto generic   # TCP line protocol placeholder + own simulator
   cargo run -p wyr -- new link <name> --proto modbus    # Modbus TCP device on tokio-modbus + links/modbus simulator
   ```
   `<name>` is `[a-z][a-z0-9_-]*` (key segment, crate `wyrm-link-<name>`, `Driver::NAME`). Templates: `tools/wyr/templates/link/{generic,modbus}/`.
2. Add `"links/<name>"` to `[workspace] members` and `wyrm-link-<name> = { path = "links/<name>" }` to `[workspace.dependencies]` in the root `Cargo.toml` (the command prints both lines).
3. Run `cargo test -p wyrm-link-<name>` — the generated tests pass before any change.
4. Replace the placeholder protocol:
   - Parameters: one `#[derive(Params)]` struct per kind (`Conn`, `Dev`, `Point`). Attributes: `default`, `min`, `max`, `desc`, `name`, `enum` (with `#[derive(ParamEnum)]`), `secret` (secrets come from the link secret store, never from params or logs). Use a hand-written `Params` impl only for cross-field rules (see modbus `Point`).
   - `open`: connect with a timeout; every error is `DriverError::Transport`.
   - `ping`: a protocol exception means the device is alive (`Ok`); no answer is `DriverError::Device`.
   - `plan`: group points into as few reads as possible (address spans, max count); it is cached until the group changes.
   - `poll`: one result per point; a protocol exception is `DriverError::Point` for the affected points only; a broken transport is `Transport`.
   - `write`: no optimistic update — the framework reads the point back. Refuse read-only points with `DriverError::Point`.
   - `point_meta`: type, unit, `writable`. `poll_period`, `ping_period`, `io_timeout` from the params.
   - Make sure a late reply after a timeout cannot be taken for the next request (transaction or sequence ids).
5. Extend the simulator (`src/sim.rs`, feature `sim`) with the device's behaviour and failure modes (exceptions, silence, disconnect), and the tests in `tests/sim.rs`: values and data types, point errors, write + read-back, silent device → `uncertain/stale` then `bad/comm_fail`, connection down → `failed` and children `stopped_by_parent`. Tests poll all the time (the default) and use generous waits (10 s).
6. To run it from `wyrmd`, register the driver in `crates/wyrmd/src/lib.rs` (params validation, `start_boxed::<…>`, `run_link`).
7. Check: `cargo fmt --all`, `cargo clippy --workspace --all-targets -- -D warnings`, `cargo test --workspace`.

## Rules
- All I/O has timeouts; honest quality; never log secrets, `ptok` or values above `trace`.
- One wire codec (`minicbor`, canonical CBOR); no `serde` in drivers.
- The connector owns its subtree and re-declares it on every (re)connect; the broker stores nothing for it.
