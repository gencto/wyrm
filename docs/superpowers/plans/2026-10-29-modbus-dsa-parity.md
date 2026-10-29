# Modbus link: parity with dslink-java-modbus, and better Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `links/modbus` covers every feature of IOT-DSA `dslink-java-modbus` that a site needs (data types, unit ids, write modes, folders, copy/export/import, slave mode, migration of DSA trees), keeps its own strengths (honest quality, FC22/RMW, reconnect with backoff, write levels), and adds what DSA lacks (per-device diagnostics, commissioning actions, DSA import).

**Architecture:** Protocol work stays in `links/modbus` (`codec.rs`, `lib.rs`). Features any driver can use go into the driver framework of `crates/wyrm-link-sdk` (`driver/mod.rs`, `driver/framework.rs`, `driver/persist.rs`) as optional hooks with defaults, so `mockdev` and existing configs keep working unchanged: driver actions, diagnostics counters, folders, branch copy/export/import, a server (slave) kind.

**Tech Stack:** Rust, `tokio-modbus` 0.17 (client, `tcp-server`, `rtu-server`, Read Device Identification FC43/14), `tokio-serial`, the WYRM driver framework (ADR 0004).

**Spec:** `docs/superpowers/specs/2026-10-29-modbus-dsa-comparison.md` (committed summary) and the owner's request (2026-10-29): "our solution must be better than theirs; add what is needed for parity and win on the strong sides". Reference: `dslink-java-modbus` (commit 0745d7d, cloned at `/private/tmp/claude-501/-Users-gencto-Projects-personal-rust-wyrm/86b080f0-67c9-44ac-906e-88cc89576310/scratchpad/dsa-java-modbus`, read only), the comparison `/private/tmp/claude-501/-Users-gencto-Projects-personal-rust-wyrm/86b080f0-67c9-44ac-906e-88cc89576310/scratchpad/modbus-compare.md` (99 rows with file:line on both sides), ADR 0004 (driver framework), `CLAUDE.md` "Next: Iteration 1" item 6 (the Modbus feature list). Where this plan rules on a gap, the ruling is binding and goes into ADR 0004 / `docs/modbus.md` in Task 9.

## Global Constraints

- English code, comments and commits; commit straight to `main` and push after each task.
- Pre-push, all must pass: `cargo fmt --all -- --check`; `CARGO_TARGET_DIR=target/r199 cargo +1.99.0 clippy --workspace --all-targets --all-features -- -D warnings`; tests of every touched crate with `--all-features`; `cargo test -p wyrmd --all-features --test e2e` when the SDK, a link or wyrmd changes. Check `gh run list --limit 3` after the push.
- **Existing stored configs keep loading.** A link's params live in the registry and in the link's sealed `data_dir` tree (`driver::persist`). Every new param has a default; no param is renamed or changes meaning (the `scale`/`offset` semantics stay: value = raw × scale + offset). A test loads a config written by the current code (fixture captured before the change) after each task that touches params.
- **Framework changes are optional hooks with defaults** on `trait Driver` or `Params`; `links/mock`'s `mockdev` and every existing driver test pass unchanged.
- Never log secrets, `ptok` or `~val` values above `trace`. Wire enums via `wire_enum!`. No `as u8`.
- Action levels follow ADR 0004: reads `read`, value writes `write`, anything that changes the tree or configuration `config`. DSA puts every action at `READ` (a DSA defect we do not copy).
- Disk is limited: no `cargo clean`. Do not restart the running demo (the controller does that and runs `wyr probe` on central 8445, edge 8444, plant 8446).

## Rulings (gaps decided here; the owner checks them)

1. **Scaling semantics stay ours** (`raw × scale + offset`). DSA divides (`raw / scaling + scaling offset`, `SlaveNode.java:326`) and its `offset` is the register address. A migrating user gets correct values through `import_dsa` (Task 7), which converts `scale = 1/scaling`, `offset = scaling offset`, `addr = offset`; `scaling = 0` is refused. The guide puts a warning table first (Task 9).
2. **Unit id 0…255, default 1.** On serial and RTU-over-TCP, 0 is broadcast: a write is sent without waiting for a reply, a read is refused (`invalid_parameter`). On Modbus TCP, 0 and 255 are ordinary units (many TCP servers ignore the unit or expect 0/255).
3. **New data types** (names in our lowercase style): `u32_m10k`, `i32_m10k`, `u32_m10k_wswap`, `i32_m10k_wswap` (value = hi × 10 000 + lo), `u32_wbswap`, `i32_wbswap`, `f32_wbswap` (DCBA: words and bytes swapped), `bcd32_wswap`, `bits16` (a register as an array of 16 bools, bit 0 first; writable on holding: writes the whole word). Existing names keep their exact byte order; the guide maps each DSA name to ours.
4. **Coil and discrete tables default to `binary`**; a non-binary dtype on a bit table stays an error.
5. **`write_mode = single` writes a multi-register value as a series of FC6** (lowest address first; DSA "Never"); a failure part-way reports the error and the read-back shows the device's real state. FC16 and FC15 are bounded at 123 registers / 1968 bits per request: a writable point with more `regs` is refused at add/edit.
6. **Per-request `retries`** on both connection kinds: 0…5, default 0 (so a stored config keeps its timing); the guide recommends 1 on RS485. A retry repeats the same request after a timeout only (an exception or I/O error is not retried).
7. **No late reply is taken for a later request on RTU** (serial and RTU over TCP). `tokio-modbus` 0.17 checks the reply's unit id and function code (`service/rtu.rs:78-90`) but cannot drain input, so a late reply to an earlier read of the same unit and function would be taken. After a timeout on an RTU transport the driver therefore reopens the transport before the next request (a local serial reopen or one TCP reconnect; counted in the diagnostics as `reopens`). Modbus TCP needs nothing: the MBAP transaction id matches replies. A test with the simulator (RTU over TCP) delaying one reply proves the next read gets its own reply.
8. **The poll's whole-operation bound grows with the plan**: a new framework hook `fn poll_timeout(conn, plan) -> Duration` (default: `io_timeout(conn)`); Modbus returns `timeout_ms × (1 + retries) × spans + 1 s`.
9. **Heartbeat**: device param `republish_s` (0 = off, default 0, max 3600): an unchanged value is published again after that long (DSA republishes every 60 s). Framework hook `fn republish(dev) -> Option<Duration>` (default `None`).
10. **Folders**: the framework gains an optional `Folder` level between Device and Point, nested at most 4 deep, purely organisational (no params of their own except `name`), with `add_folder`, `remove` (cascades), `edit {name}` = not supported (rename is out, ruling 14). Points keep their id; their key gains the folder path. Driver opts in with `const FOLDERS: bool = false` (Modbus: `true`).
11. **Copy / export / import**: framework actions (config level): `copy {name}` on connection, device, folder and point (a deep copy under the same parent with a new id; the copy starts disabled when it is a connection or device, so it does not double-poll a device by surprise); `export` on connection, device and folder → `{json}` (params of the whole branch, secrets left out and marked `"secret": "<not exported>"`); root `import {json, name?, overwrite?}` and device/folder `import` for a branch of the matching kind. Export format: `{"format": "wyrm-driver-branch/1", "driver": "<NAME>", "kind": "...", "params": {...}, "children": [...]}`.
12. **Diagnostics** (framework, every driver): a connection and each device get read-only value children `requests`, `errors`, `timeouts`, `exceptions`, `last_rtt_ms`, `avg_rtt_ms` (EWMA α = 0.1), published on change at most once every 10 s (and at once on a read of the node); counters reset on (re)start. Hidden from nothing: they are ordinary values (historian can watch them).
13. **Commissioning actions** (Modbus, via a new framework hook for driver actions, `fn actions(kind) -> Vec<(name, ActionMeta)>` + `fn invoke(t, kind, id, params, action, args)` on the owner task): device `read_registers {table, addr, count ≤ 125, dtype?}` (read level) → raw words and the decoded value; device `read_device_id` (read level, FC43/14 basic+regular objects) → map; connection `scan_units {from = 1, to = 247, timeout_ms = 200}` (config level; one probe read per unit, stops on the first transport error) → list of answering units. All bounded by `io_timeout`; they never disturb polling more than one request at a time (owner task).
14. **Not done, on purpose**: Modbus ASCII and UDP (`tokio-modbus` has neither; rare in the field) — the guide says so; parity MARK/SPACE (`serialport` lacks it); `rename` (ids are keys: history watches, ACL and flows would break; `copy` + `remove` covers it); "zero on failed poll" (dishonest values; our quality ladder `uncertain/stale → bad/comm_fail` is the answer — the guide explains how a consumer treats bad quality). Batch polling on/off stays `max_regs = 1` (documented).
15. **Slave (server) mode**: a third and fourth connection kind `ip_slave {listen_host, listen_port}` and `serial_slave {serial params}`; under it devices are unit ids served; under them points (table, addr, dtype, regs, scale, offset, writable_by_master). A point's value comes from the tree (`~set`, level write) and is served to masters; a master write to a `writable_by_master` point updates the point's value (published, audited as the link). Unknown addresses answer exception 2 (illegal address); a read-only point written by a master answers exception 3. Framework: a server kind is a connection kind whose `open` returns a running server and whose points are not polled (`Driver::is_server(conn) -> bool`, default false). Listener on loopback by default (`listen_host = "127.0.0.1"`); another address is allowed (adding a connection is already a config action), logged at `warn` and stated in the connection's status node, and the guide warns that Modbus has no authentication.
16. **Docs truth**: ADR 0004's sketch (timeout 500, `retries`) and CLAUDE.md's "verified against diagslave" are corrected to what the code does (Task 1 for the claim, Task 9 for the ADR sketch).

## Review Focus

1. **A config stored before this plan still loads and polls the same values** after every task (fixture test). Owner of the test: Task 1 (fixture), re-run in every later task.
2. **A dead slave on a multi-drop RTU bus** (no reply) does not poison the other units: the next unit's reply is its own, and reopens happen at most once per timeout (never in a loop without a request). Test in Task 2.
3. **DSA import of a scaled point** (`scaling = 10`, `scaling offset = 2`, raw 250) shows exactly 27.0, and writes 27.0 back as raw 250. Test in Task 7.
4. **Slave mode race**: a master write and a tree `~set` to the same point — last writer wins, the published value equals what the next master read returns. Test in Task 8.
5. **Folder remove** cascades points, stops their polling, removes them from the persisted tree, and a restart does not bring them back. Test in Task 5.

---

### Task 1: Codec and param parity

**Files:** `links/modbus/src/codec.rs`, `links/modbus/src/lib.rs`, `links/modbus/tests/sim.rs`, `links/modbus/tests/fixtures/config-2026-10-29.json` (new: a config written by the current code), `CLAUDE.md` (diagslave claim).

- [ ] **Step 1: Capture the fixture first** (before any code change): a connection (IP and serial), a device and one point of every current dtype, as the `to_map` of each kind, saved as JSON. Test `stored_config_still_loads`: every entry parses with `from_map` and `to_map` gives the same map back.
- [ ] **Step 2: Failing tests** in `codec.rs`/`tests/sim.rs` for rulings 2–5: round trip of every new dtype against hand-computed words (`u32_m10k` 1234 × 10 000 + 5678 = 12 345 678 from `[1234, 5678]`; `_m10k_wswap` from `[5678, 1234]`; `*_wbswap` DCBA of `0x11223344` = `[0x4433, 0x2211]`; `bcd32_wswap`; `bits16` array of 16 bools both ways); refusals (`m10k` word > 9999 → `OutOfRange`); on RTU: unit 0 read refused, unit 0 write sent without waiting for a reply (simulator sees it); on TCP: units 0 and 255 read and write normally; a coil point without `dtype` parses as `binary`; a writable `varchar` with `regs = 124` refused with the field named.
- [ ] **Step 3: Implement.** Serial allowlist: add `ttySC`, `ttyM`, `ttyMXUSB`, `ttyMI`, `ttyRP`, `ttyXR`, `ttyCH343USB`, `ttyHS`, `ttyMSM` (Linux) and keep the refusals of `/dev/tty`, `/dev/ttyN`, `/dev/ttyprintk`; a test lists accepted and refused names.
- [ ] **Step 4:** CLAUDE.md: "Verified against `diagslave` and a real device" → "Tested against the built-in simulator (`wyrm-modbus-sim`); not yet verified against `diagslave` or a real device". Run the pre-push checks, commit `Modbus: data types, unit ids and defaults of the DSA link; a stored config still loads`, push.

### Task 2: Writes, retries, late replies, poll bound, heartbeat

**Files:** `links/modbus/src/lib.rs`, `links/modbus/src/sim.rs` (simulator: delay one reply, drop one request, count FC6/FC16), `crates/wyrm-link-sdk/src/driver/{mod.rs,framework.rs}` (hooks `poll_timeout`, `republish`), tests in both crates.

- [ ] **Step 1: Failing tests:** `single_mode_writes_a_series_of_fc6` (an `f32` write in `single` mode → two FC6, lowest address first, no FC16); `a_timeout_is_retried_once` (simulator drops the first request; `retries = 1` → value good, no quality change); `an_exception_is_not_retried`; `a_late_reply_is_not_taken` (Review Focus 2, RTU over TCP: unit 2 answers 300 ms late with timeout 200; the next read of unit 2 at another address and of unit 3 return their own values; exactly one reopen); `poll_bound_grows_with_spans` (a plan of 10 spans with timeout 100 ms and one slow span is not cut at 4 × 100 ms); `republish_after_n_seconds` (framework test with `mockdev` or a test driver: an unchanged value is put again after `republish_s`; 0 = never).
- [ ] **Step 2: Implement** rulings 5–9. Hooks get defaults so `mockdev` is unchanged.
- [ ] **Step 3:** pre-push checks; commit and push.

### Task 3: Framework driver actions and diagnostics

**Files:** `crates/wyrm-link-sdk/src/driver/{mod.rs,framework.rs}`, framework tests; `links/modbus/src/lib.rs` (counts requests, errors, timeouts, exceptions and RTT in `io()`).

- [ ] **Step 1: Failing tests** (framework, with a test driver): `driver_actions_are_declared_and_run_on_the_owner_task` (an action declared by `actions(kind)` appears on the node with its level; `invoke` runs between polls, never concurrently with a poll of the same connection; its error status reaches the caller); `diagnostics_are_published_on_change_at_most_every_10_s` (counters increase with requests; `last_rtt_ms` and `avg_rtt_ms` move; no publish when unchanged; reset on restart).
- [ ] **Step 2: Implement** rulings 12 and the hook half of 13. The driver reports outcomes through a small counter API passed to I/O methods (or returned with each result); choose the form that keeps `Driver` methods simple and say which in the report.
- [ ] **Step 3:** pre-push checks; commit and push.

### Task 4: Modbus commissioning actions

**Files:** `links/modbus/src/lib.rs`, `links/modbus/src/sim.rs` (FC43/14 answers), `links/modbus/tests/sim.rs`.

- [ ] **Step 1: Failing tests:** `read_registers_returns_words_and_value` (`holding 10 count 2 dtype f32` → words and 21.5); `read_registers_bounds` (`count = 126` refused); `read_device_id_returns_objects` (vendor, product code, revision from the simulator; a device without FC43 → `not_supported`); `scan_units_finds_answering_units` (simulator answers units 1 and 7 → `[1, 7]`; timeouts skip); levels: `read_registers`/`read_device_id` read, `scan_units` config.
- [ ] **Step 2: Implement** ruling 13 on the Task 3 hook.
- [ ] **Step 3:** pre-push checks; commit and push.

### Task 5: Folders in the framework

**Files:** `crates/wyrm-link-sdk/src/driver/{mod.rs,framework.rs,persist.rs}`, framework tests, `links/modbus/src/lib.rs` (`const FOLDERS: bool = true`).

- [ ] **Step 1: Failing tests:** `add_folder_nests_points` (`<conn>/<dev>/<f1>/<f2>/<point>` declared; polling unchanged: the plan groups by device, not folder); `depth_limit_is_4`; `folder_remove_cascades` (Review Focus 5: points gone, polling stopped, persisted tree updated, a restart keeps them gone); `driver_without_folders_has_no_add_folder` (`mockdev` unchanged); `stored_config_without_folders_loads` (Task 1 fixture).
- [ ] **Step 2: Implement** ruling 10. Point ids stay unique per device across folders (an add with an id used elsewhere on the device is refused), so `PointId`, writes and plans need no folder awareness.
- [ ] **Step 3:** pre-push checks (full e2e: the framework changed); commit and push.

### Task 6: Copy, export and import of branches

**Files:** `crates/wyrm-link-sdk/src/driver/framework.rs` (+ a new `driver/branch.rs` for the format), framework tests.

- [ ] **Step 1: Failing tests:** `copy_device_is_deep_and_disabled` (folders and points copied, new id, `enabled = false`); `copy_point_under_same_parent`; `export_leaves_secrets_out`; `import_round_trip` (export a connection → import under a new name → same params and children; secrets marked missing must be re-entered, the import says which); `import_refuses_wrong_kind_or_driver_or_format` (field named); `import_overwrite` (false refuses an existing id); levels are config.
- [ ] **Step 2: Implement** ruling 11.
- [ ] **Step 3:** pre-push checks (full e2e); commit and push.

### Task 7: DSA import

**Files:** `links/modbus/src/dsa.rs` (new), `links/modbus/src/lib.rs` (root action `import_dsa {json, name?}` at config level, on the Task 3 hook, building a branch and handing it to the Task 6 import), `links/modbus/tests/dsa.rs`, `links/modbus/tests/fixtures/dsa-nodes.json` (a hand-written DSA `nodes.json` subtree in the attribute format of `SlaveFolder.java`/`ModbusConnection.java`/`IpConnection.java`/`SerialConn.java`: one IP and one serial connection, a device with a folder, points of several DSA types and scalings).

- [ ] **Step 1: Read** the DSA sources (v1, `dslink-java-modbus` 0745d7d — the link the owner named; no real DSA Modbus `nodes.json` exists on the owner's machine, checked 2026-10-29) for the exact attribute names and value encodings (`ATTR_*` constants, `DataType` names, `PointType` names, transport and parity enums, `use multiple write commands`, polling interval in seconds, `zero on failed poll`) and write the fixture from them. Every DSA field gets a mapping or a named, reported drop.
- [ ] **Step 2: Failing tests:** `scaled_point_reads_and_writes_exactly` (Review Focus 3: `scaling 10`, `scaling offset 2`, raw 250 → 27.0; write 27.0 → raw 250); `scaling_zero_refused`; `every_dsa_type_maps` (each DSA `DataType` → our dtype or a named refusal); `folders_kept`; `poll_interval_moves_to_points`; `transport_udp_or_ascii_reported` (imported disabled with a note, ruling 14); `zero_on_failed_poll_reported_as_dropped`; `report_lists_every_drop`.
- [ ] **Step 3: Implement.** The task reviewer checks the fixture against the DSA source independently. The action answers `{created: [...], dropped: [{path, field, reason}], disabled: [...]}`.
- [ ] **Step 4:** pre-push checks; commit and push.

### Task 8: Slave (server) mode

**Files:** `crates/wyrm-link-sdk/src/driver/{mod.rs,framework.rs}` (server kinds: not polled; values from the tree; a channel for values written by the remote side), `links/modbus/src/lib.rs` + `links/modbus/src/slave.rs` (new; `tokio-modbus` `tcp-server` / `rtu-server` features), tests.

- [ ] **Step 1: Failing tests:** `master_reads_tree_values` (a `tokio-modbus` client reads holding 10 as the tree's `f32` 21.5 with scaling); `master_write_updates_the_tree` (writable point; published value and audit); `read_only_point_written_by_master_gets_exception_3`; `unknown_address_gets_exception_2`; `tree_set_and_master_write_race` (Review Focus 4); `non_loopback_listen_is_flagged` (warn log and status text); `rtu_slave_answers_over_a_pty` (Linux CI only if a pty pair is available; else a framed codec test).
- [ ] **Step 2: Implement** ruling 15. Write a short ADR `docs/adr/0024-driver-server-kinds.md` (the framework part of ruling 15: why a server is a connection kind, how values flow both ways, why the listener defaults to loopback).
- [ ] **Step 3:** pre-push checks (full e2e); commit and push.

### Task 9: Guide, ADR update, demo probe

**Files:** `docs/modbus.md` (new), `docs/adr/0004-*.md` (sketch corrected; folders, actions, diagnostics, copy/export/import, server kinds), `docs/links.md` (pointer), `links/probe/scenarios/modbus.json` (built-in, runs on sites that have `plc1`; `require` skips elsewhere), `CLAUDE.md` (the Modbus line).

- [ ] **Step 1: Guide**: tree and actions; every param with default and bound; data types with a DSA → WYRM name table and byte orders; scaling warning table first (ruling 1); write modes; retries and RTU timing; quality ladder vs "zero on failed poll"; folders, copy/export/import; DSA import with its report; diagnostics and commissioning actions; slave mode and its exposure (no authentication in Modbus); what is not supported and why (ruling 14); a "better than DSA" section listing the DSA defects we avoid (comparison file, "Помилки в DSA").
- [ ] **Step 2: Probe scenario** on edge `plc1`: `require` the connection; `read_registers` on `ahu1`; a folder add/remove with a point copy; `export` then `import` under a new name and remove it (`cleanup` steps); a diagnostics value exists.
- [ ] **Step 3:** pre-push checks; commit and push. The controller restarts the demo and runs `wyr probe` on the three sites.
