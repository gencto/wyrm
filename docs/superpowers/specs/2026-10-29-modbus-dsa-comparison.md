# Modbus link vs IOT-DSA dslink-java-modbus — comparison summary (2026-10-29)

Reference: https://github.com/IOT-DSA/dslink-java-modbus at commit `0745d7d` (2021-09-03), 21 Java files, about 4.6k lines; clone it again to check any row. Ours: `links/modbus` on the driver framework (ADR 0004). The full row-by-row table (99 rows with file:line on both sides) was produced in the session of 2026-10-29; this file keeps its conclusions.

Counts: SAME 29, OURS BETTER 26, MISSING IN OURS 21, DIFFERENT (gap) 9, DIFFERENT (deliberate) 7, OURS ONLY 7.

## Gaps, most important first (effort S/M/L)

1. Scaling is inverted: DSA `raw / scaling + scaling offset` (`SlaveNode.java:326`), ours `raw × scale + offset` (`codec.rs:230`); DSA `offset` is the register address. No importer of DSA trees. (M; a guide note alone is S.)
2. Unit id bounded 1…247 and required; units 0 and 255 cannot be used. (S)
3. Missing data types: INT32M10K/UINT32M10K (+SWAP), INT32SWAPSWAP/UINT32SWAPSWAP (DCBA), BCD32SWAP; our `*_bswap` is a different byte order. (S)
4. `write_mode = single` still sends FC16 for multi-register values (no series of FC6 like DSA "Never"); `regs` allows 125 while FC16 carries at most 123. (S)
5. No folders under a device (the tree has exactly three levels). (L)
6. The serial allowlist refuses real ports (`/dev/ttySC*`, `/dev/ttyM*`, `/dev/ttyMXUSB*`, …). (S)
7. No slave (server) mode (DSA "setup local slave"); deferred to iteration 6 in CLAUDE.md. (L)
8. No UDP or Modbus ASCII transport (`tokio-modbus` has neither). (M each)
9. No import/export of a branch, no "make copy", no rename. (S–M)
10. No republish of unchanged values (DSA republishes every 60 s). (S)
11. No per-request retries. (S)
12. Coil/discrete points need an explicit `dtype = binary`. (S)
13. No "register as 16 bools". (S)
14. The poll group bound is always 4 × `timeout_ms`; a late RTU reply after a timeout can be taken for the next request. (S)
15. No batch-polling switch (workaround `max_regs = 1`), no parity MARK/SPACE. (S/M)
16. No "zero on failed poll" — deliberate (honest quality ladder). (S if wanted)

## DSA defects we do not have (read from code, not run)

- A connection that fails at DSA start is never retried; serial reconnects once only.
- Every DSA action is at `Permission.READ` (anyone who can read can reconfigure).
- Writing a bit in a register has no FC22 and no read-modify-write (it overwrites the other bits).
- The inverse scaling on write is wrong.

## Documentation found wrong in our repo

- ADR 0004's sketch shows timeout 500 and `retries`; the code has timeout 1000 and no `retries`.
- CLAUDE.md says the driver was verified against `diagslave`; the tests only use the built-in simulator.
