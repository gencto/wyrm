# ADR 0026 — History sync to external databases

**Status:** proposed · 2026-10-31 (owner request: send the edge historian's data to MySQL, MongoDB, PostgreSQL, InfluxDB and DynamoDB; not native in the broker, extensions installed as links; three decisions open, see the end).

## Context
The embedded historian (ADR 0014) records watched points into day files of redb on the edge. Sites need the same data in a central database. The owner named five targets: MySQL, MongoDB, PostgreSQL, InfluxDB, DynamoDB.

The reference is DSA `dslink-java-historian-dynamodb` 0.2.2 (read 2026-10-31: `DynamoDBProxy`, `BufferPurger`). It is a whole historian of its own: its watch groups write to DynamoDB, which is the primary store, and Get History reads DynamoDB. A local ETSDB database is only a buffer while DynamoDB cannot be reached: queued records go there, a background runner sends them back in batches (`Batch Write Max Records`, `Batch Write Min Interval`), deletes what was sent (`delete(series, 0, lastTs)`), and `BufferPurger` deletes the oldest unsent hour of every series while the buffer is over `Maximum Buffer Size`. Records are keyed by watch path and time, so a resend overwrites. Records carry an `expiration` for DynamoDB TTL, as deletes there cost write capacity.

WYRM differs in one point that drives this design: the broker's historian is the primary store on the edge. Get History, the history mark and chart in the explorer (ADR 0016), `~val?history=` (D2) and the history of downstream points (ADR 0020) all read it. A sync that deletes each row once it is sent would leave the edge with no history.

What a link can do today:
- A portable App (ADR 0023) runs the same code as a WASM component (world `wyrm:app`) or as a process package; the scheduler and the DQL link ship both ways.
- The WASM host gives `tcp-connect(addr, port)` with an IP literal only, checked against the link's `NetPolicy`. No DNS, no TLS. Every managed database (RDS, Atlas, DynamoDB, InfluxDB Cloud) needs a host name and TLS.
- History is read with `get <point>/~val?history=` (rights as `subscribe`, at most 5 000 rows per reply, 4 reads at a time) or Get History on `sys/history/…` (`config`). Neither has a cursor: a reader cannot ask "everything written since my last batch".
- The store keeps rows `(series, t) → [v, q]`; a row with the same key replaces the old one, and a row may arrive up to 31 days late. A cursor on time misses a late row written into an earlier day.

## Decision
- **Not in the broker binary.** A database client in `wyrmd` would grow the binary for every site, and adding one would need a new build and a restart of the edge. Each target is a link package that the operator installs where it is needed (ADR 0011, 0021).
- **The historian stays the store; links forward.** The historian gets a change feed with a cursor per sink. Sinks read batches from it and confirm them. Only the historian deletes, by its own rules. A sink never deletes and never needs `config` on `sys`.
- **Change journal in each day file.** Table `CHANGES: seq u64 → (series u32, t u64)`, written in the same transaction as the row, so a row and its sequence number commit together. `seq` is one counter for the store, kept in `index.redb` and taken in blocks so a crash leaves gaps, never repeats. A row written again (same key, a late or replaced value) gets a new `seq`, so it is sent again. Each day file records its lowest and highest `seq`; a read from a cursor opens only files whose range is above it. Deleting a day file deletes its journal with it.
- **Sinks are historian state.** `sys/history/sinks/<name>`: the link id, the watch groups it takes (default all), `confirmed_seq`, and values `rows_sent`, `lag_rows`, `lag_s` (age of the oldest unconfirmed row), `last_batch`, `last_error`. Actions Add Sink, Edit, Remove, Reset Cursor {to start | to now}. Registry ops in the historian section (SCHEMA bump), audited (`history_sink`).
- **The feed.** The link asks `next {after, max}` on its own feed key `wy/<site>/sys/history/feeds/<link>`; the answer is rows `{seq, key, t, v, q}` with `seq > after`, at most `max` (≤ 5 000) and at most 1 MiB, oldest `seq` first, rows of its watch groups only. `after` confirms every row up to it, so the confirmation is the next request (at least once). The link signs with its requester key (ADR 0013, subject `link:<id>`); the historian trusts that key at `read`, scoped to that one feed key, as the admin trusts upstream keys today. The router ACL lets each link's session query its own feed key only, as with its overlay key (ADR 0016).
- **Deleting.** The current rules stay: Retention Days, then Auto Purge by Disk Space Remaining (ADR 0014). New: with `keep_after_sync_days` set (default off), a whole day file goes once every sink has confirmed its highest `seq` and the day is older than that many days. `0` keeps only what is not sent yet, as the DSA buffer does.
- **Delivery is at least once.** A batch can be sent twice after a lost reply or a restart. Every sink writes with the key `(site, point key, t)` and replaces on conflict, so a resend changes nothing.
- **One package per target, one shared core, one form for all (owner, 2026-10-31).** A crate `wyrm-history-sync` (cursor, batch size, wait between batches, back-off while the target is down, the counters, secrets in the connection parameters, sealed by the framework) and one package per target, so a device installs only what it uses. Every target is a portable App with its own protocol client over the host's `tcp-connect`/`tls-connect`, no native driver crates (`sqlx`, `mongodb`, AWS SDK): the same code ships as a WASM package (the default) and as a process package, and behaves the same in both. A process package is not faster here in any way that matters: a batch is one or two round trips to the database, and encoding 5 000 rows in WASM takes well under a millisecond; what native drivers would save is our own protocol code, at the cost of a build per architecture and a process per sink.
- **Host: TLS for portable Apps.** World `wyrm:app` adds `tls-connect(host, port, timeout-ms)`: the host resolves the name, checks every resolved address against the `NetPolicy` (which gains host-name entries), verifies the certificate against the system roots or a CA from the link's parameters, with rustls (ring) that `wyrmd` already links. The data stays in the component; the keys never do. Every target that needs TLS waits for it, in both forms.

| Target | Protocol | TLS | Idempotent write | Our client covers |
|---|---|---|---|---|
| InfluxDB (v2, v3) | HTTP, line protocol | cloud: yes | same measurement, tags and time overwrite | HTTP/1.1 request and status only |
| PostgreSQL | wire protocol (sans-IO `postgres-protocol`), SCRAM-SHA-256 | usually | `INSERT … ON CONFLICT DO NOTHING`, key `(site, key, t)` | startup, auth, one multi-row insert per batch, ping |
| DynamoDB | HTTPS, JSON, SigV4, `BatchWriteItem` (25 items, 16 MiB) | always | partition key `site/key`, sort key `t`; TTL attribute as DSA | SigV4 signing, retry of `UnprocessedItems` |
| MySQL | wire protocol | usually | `INSERT IGNORE`, primary key `(site, key, t)` | handshake, `caching_sha2_password` over TLS only (no RSA exchange), multi-row insert, ping |
| MongoDB | OP_MSG, BSON (`bson` crate, builds for wasm32), SCRAM-SHA-256 | Atlas: always | unique index `(site, key, t)`, `insert` with `ordered: false`; time-series collection optional | `hello`, auth, insert, ping |

- **Order of work.** 1) journal, sinks and the feed in `wyrm-history` and the admin, with e2e (late row resent, resend after a lost reply, `keep_after_sync_days`); 2) `tls-connect` in world `wyrm:app`; 3) `wyrm-history-sync` and the InfluxDB and PostgreSQL packages; 4) DynamoDB, MySQL, MongoDB. Each client is tested against an in-crate fake server and, in an ignored e2e, against the real database in a container.

## Consequences
- The broker grows by the journal and the feed only; targets add nothing to sites that do not use them.
- Each row costs about 16 more bytes on disk (the journal entry).
- A sink that stops confirming holds no data back unless `keep_after_sync_days` is set; with it set, its `lag_rows` grows and its day files stay until Retention Days or Auto Purge remove them.
- The central database keys rows by the point's full key (`wy/<site>/…`), so several sites can share one table without the prefixes DSA needs.

## Alternatives
- **A sink inside `wyrmd` for each database:** a new build and restart for each target, a larger binary everywhere (the owner's two objections).
- **Remote database as the primary store (as DSA):** the edge would read its own history over the WAN; offline sites lose Get History.
- **Delete each row once sent (as the DSA buffer):** possible as `keep_after_sync_days: 0`, not as the only mode, for the same reason.
- **A cursor on time instead of a journal:** misses late rows and rows written again.
- **Sinks read `~val?history=` per point:** one query per point per batch, no cursor, no confirmation.
- **TLS inside the component (rustls with RustCrypto):** about a megabyte per component, slower under the fuel limit, and every package would carry its own copy of the roots.

## Open decisions (owner)
1. **Disk full with unsent rows.** Proposed: Auto Purge and Retention Days still delete the oldest day, sent or not, as DSA does, and count `rows_dropped_unsent`. The other choice is to stop recording until the sinks catch up.
2. **`keep_after_sync_days` default.** Proposed: off, so adding a sink deletes nothing by itself.
3. **What a sink takes.** Proposed: a list of watch groups, default all.
