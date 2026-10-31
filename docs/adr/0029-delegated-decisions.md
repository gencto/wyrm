# ADR 0029 — Decisions delegated by the owner

**Status:** accepted · 2026-10-31 (owner: "my answers decide nothing; make the changes yourself and record each rule in the documentation").

## Context
Several questions stayed open in `CLAUDE.md` and in the notes of earlier work (ADR 0022, 0024, 0027, 0028, the Modbus parity plan). Most of them were already answered by the code; they were only not written down as decisions. The owner delegated them on 2026-10-31. This ADR records each one in one place, with what it costs if it is wrong. User guides carry the rules that users meet.

## Decisions

### 1. Selector parameters are joined with `&`
Spec 01 writes `key?param=value&…`; a `match` value uses `;` inside it (`is:<code>;unit:°C`). Zenoh 1.10 `Parameters` splits on `;`, so every SDK reads the raw selector string and splits on `&` itself (checked through a router hop). No spec change.
*If wrong:* a client that builds selectors with Zenoh's `Parameters` sends one long parameter; the responder answers `invalid_message`.

### 2. The requester sets the QoS of a request
A Zenoh reply takes the QoS of its query, so the requester chooses it: `wyrm-client` (and through it the gateway, the flow engine, the FFI and `wyr`) sends `~set` and `~act/*` queries with `InteractiveHigh + Block + express`, and `~meta`/`~val` reads with the defaults of spec 05. A process link's SDK does the same for its own requests. Spec 05's QoS table describes the query; the responder does not set a reply QoS.
*If wrong:* a third-party client with default QoS gets its command replies at `Data` priority behind value traffic.

### 3. A `ptok` is used once per responder
Spec 04 0.2.11 states it: each responder remembers a token's `jti` until its `exp` and refuses it a second time (`permission_denied`). The memory is per process and not kept across a restart, so after a restart a token seen before can be used again until its `exp`. The SDK refuses a token whose `exp` is more than 15 minutes ahead (`MAX_TOKEN_TTL_S`), which bounds that window. A full cache (65 536 tokens that have not expired) refuses new tokens until one expires rather than forgetting one.
*If wrong:* a captured token replays once after a responder restart, within 15 minutes. TLS on every non-loopback hop makes capture the hard part.

### 4. The broker persists its own state with `wyrm-state`, not a Zenoh volume
The registry (links, grants, ACL inputs, peers, profiles `pub/**`, history watches, options), the gateway users, the flow definitions and their node state, broker storage and the historian are kept by their owners (WAL + postcard snapshot, or redb for storage and the historian). Zenoh's storage manager keeps only `wy/**/~val` in memory (the last value for a late subscriber). The rocksdb volume is not used: it exists only as a dynamic `.so`, which principle 2 forbids.
*If wrong:* nothing is lost on restart that the owner of a key does not declare again; a `~val` of a link appears again on its next sample.

### 5. Links are tested against their own simulators
Every protocol link has a simulator in its crate, and the tests run against it. No link has been checked against a real device or a third-party simulator (`diagslave` for Modbus) yet; the guides say so in their limits. This is a gap in evidence, not a decision to skip it.

### 6. rustls stays pinned at `=0.23.45`
zenoh-link-tls 1.10.1 reads and writes one TLS session from two tasks; rustls 0.23.46 checks the shared state on every write, and the race shows as SIGBUS or dropped TLS sessions. The pin is in the root `Cargo.toml` with the reason. Revisit it when Zenoh is upgraded (quarterly, with the fixture suite): drop the pin when the TLS link no longer shares one session between tasks.
*If wrong:* rustls fixes after 0.23.45 do not reach the broker until then.

### 7. Audit records sent during a reconnect can be lost
A link puts an audit record (`sys/audit/<link>`) at `Background` priority, without an acknowledgement. A record put while the link has no session to the router is dropped. The responder still refuses or answers the request as usual; only the record is missing. A resend needs an acknowledged audit path (a spec change); it is not done.
*If wrong:* the audit misses commands that ran during a broker restart or a network cut.

### 8. RUSTSEC-2023-0071 (`rsa` 0.9, Marvin timing) is accepted in `links/opcua`
async-opcua uses `rsa` for the RSA security policies of OPC UA, and no fixed `rsa` release exists. The attack needs many timed decryptions by the server under attack; the link is a client that decrypts only the server's replies to its own session. `docs/opcua.md` states it.
*If wrong:* an attacker who can time many of the link's decryptions on the network could recover a session key.

### 9. Modbus residuals stay as built
- A `~set` waits behind a running read action (`read_registers`, `scan_units`) on the same connection for at most the driver timeout (5 s) and may answer `timeout` (Modbus parity plan, ruling P33; `docs/modbus.md`).
- `ip_slave` binds its port when the connection starts. If the router still holds the port during a rebuild, the connection goes `Failed` and retries with backoff (finding M8): no separate wait is added.
- A slave answers exception 0x04 for a register whose bits the tree has not set yet, never a made-up 0 (rulings P24, P28).

### 10. A scheduler target writes only within its author's rights
Defining or changing a target stays a `config` action (ADR 0022, ruling 6). The scheduler now also keeps the author's `auth` grants (spec 04 0.2.10) with each target, as DQL does with a sink (ADR 0025 item 4), and refuses a target write outside them when it fires. A target stored before this change has no author grants and is refused until a user with config edits it again.
*If wrong:* a target that worked before stops until it is edited once.

### 11. File stores: the low items of ADR 0027/0028 are closed
- A connection name `.` or `..` is refused (`invalid_message`).
- A `206` reply must carry a `Content-Range` that starts at the asked offset; otherwise the part is refused, not used.
- A `416` reply for an offset at or past the end of a file answers `{data: [], eof: true}` with the size from `Content-Range: bytes */<size>`.
- `upload_begin` refuses a file larger than the free space of the link's disk (minus 1 GiB), checked again at each part.
- Spool cleanup runs on the blocking pool, not on a tokio worker.
- An S3 multipart upload cut by Stop or Edit is aborted (AbortMultipartUpload) before the connection closes.

## Not decided here
- New framework hooks that links asked for (per-point quality, `poll_period` with connection and device params, the sample time from the driver, `~meta` from device data, a driver-owned connection leaf) are work items in `docs/backlog.md`, not decisions.
- The `wyrm:app` world after 0.2.0 (TLS imports, a host random source) gets its own ADR.
