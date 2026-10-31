# ADR 0026 — History sync to external databases

**Status:** accepted · 2026-10-31 (owner request: send the edge historian's data to MySQL, MongoDB, PostgreSQL, InfluxDB and DynamoDB; not native in the broker, extensions installed as links; owner decisions 1–3 taken 2026-10-31, see the end).

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
- **Sinks are historian state.** `sys/history/sinks/<name>`: the link id and the watch groups it takes (owner decision 3: a list per sink, empty = all groups, so two sinks may take different groups) in the registry (`HistorianDef::sinks`, ops `PutSink`/`RemoveSink`, SCHEMA 19); the cursor (`confirmed_seq`) in the history store's `index.redb`, as it moves with every batch. Values `link`, `groups`, `confirmed_seq`, `lag_entries` (journal entries after the cursor, rows of other groups included), `rows_sent`, `rows_dropped_unsent`, `last_request`. Actions Add Sink {name, link, groups, from: start | now}, Edit, Reset Cursor {start | now}, Remove; audited (`history_sink`). A removed link takes its sinks with it.
- **The feed.** The link invokes `next {after?, max?}` on its sink node; the answer is `{rows: [{seq, key, t, v, q}], next}`: rows with `seq > after` of its watch groups, oldest `seq` first, at most `max` (≤ 5 000) and 1 MiB. `after` (default: the confirmed entry) confirms every row up to it, so the confirmation is the next request (at least once); the link asks next after `next`, which covers entries it does not take. Only numbers committed when the read starts are read (a write holds the journal until its last day commits), so a cursor never passes a row still being written. The link signs with its requester key (ADR 0013, subject `link:<id>`); the admin trusts that key at `read` on that sink's node alone, and refuses `next` from any other subject: a person who ran it would confirm rows the database never got. The router ACL lets a process link's session query its sinks' `~act/next` only (`sinks-<id>-in`/`-out`). Adding or editing a sink makes the link's requester key, starts a process link again (it takes the key in `hello`) and rebuilds the broker.
- **Deleting.** The current rules stay and never wait for a sink (owner decision 1): Retention Days, then Auto Purge by Disk Space Remaining (ADR 0014) delete the oldest day, sent or not, because the equipment keeps working and recording on the edge while the cloud may be down for long; the unsent rows lost that way are counted (`rows_dropped_unsent` on the historian and on each sink). New: `keep_after_sync_days` (default 90, owner decision 2; empty = off): with at least one sink, a whole day file goes once every sink has confirmed its highest `seq` and the day is older than that many days. `0` keeps only what is not sent yet, as the DSA buffer does. With no sink the rule does nothing.
- **Delivery is at least once.** A batch can be sent twice after a lost reply or a restart. Every sink writes with the key `(site, point key, t)` and replaces on conflict, so a resend changes nothing.
- **One package per target, one shared core, one form for all (owner, 2026-10-31).** A crate `wyrm-history-sync` (cursor, batch size, wait between batches, back-off while the target is down, the counters, secrets in the connection parameters, sealed by the framework) and one package per target, so a device installs only what it uses. Every target is a portable App with its own protocol client over the host's `tcp-connect`/`tls-connect`, no native driver crates (`sqlx`, `mongodb`, AWS SDK): the same code ships as a WASM package (the default) and as a process package, and behaves the same in both. A process package is not faster here in any way that matters: a batch is one or two round trips to the database, and encoding 5 000 rows in WASM takes well under a millisecond; what native drivers would save is our own protocol code, at the cost of a build per architecture and a process per sink.
- **One target interface, as DSA's historian SDK (owner, 2026-10-31).** DSA keeps all common work in `sdk-dslink-java/sdk/historian` (nodes, watch groups, Get History, subscriptions); a database link implements only `DatabaseProvider` (`createDbAction`, `createDb`, `dbPermission`, `deleteRange`) and `Database` (`performConnect`, `write`, `query`, `queryFirst`, `queryLast`, `close`, `initExtensions`). Here `wyrm-history-sync` owns everything but talking to the database: the link's nodes (one per connection: `status`, `error`, the counters; actions Add, Edit, Remove, Test Connection, Pause/Resume), the feed loop (`next`, confirmation), batch sizes, back-off, secrets. A target implements one trait:

  ```rust
  pub trait Target: Sized {
      /// The package and the link's root: "influxdb", "postgres", "mysql", "mongodb", "dynamodb".
      const KIND: &'static str;
      const VERSION: &'static str;
      /// Check the target's params before anything connects; an unknown key is an error.
      fn check(cfg: &Map) -> Result<(), String>;
      /// Open and authenticate (TCP or TLS through the host), with the secret from Set Password.
      fn connect(net: &mut dyn Host, cfg: &Map, secret: Option<&str>) -> Result<Self, TargetError>;
      /// Create the table, index or bucket if the parameters allow; safe to repeat.
      fn prepare(&mut self, _net: &mut dyn Host) -> Result<(), TargetError> { Ok(()) }
      /// Store one batch, replacing on `(key, t)`; `Ok` only when every row is stored.
      fn write(&mut self, net: &mut dyn Host, rows: &[Row]) -> Result<(), TargetError>;
      /// A cheap check of the connection.
      fn ping(&mut self, net: &mut dyn Host) -> Result<(), TargetError>;
      /// The largest batch it takes, e.g. DynamoDB 25 items per request.
      fn limits(&self) -> Limits { Limits::default() }
      fn close(self, _net: &mut dyn Host) {}
  }
  /// `key` is the point's full key (`wy/<site>/…`), so `(key, t)` is unique across sites.
  pub struct Row { pub seq: u64, pub site: String, pub key: String, pub t: u64, pub v: Value, pub q: Quality }
  pub enum TargetError {
      Retry(String),     // network, throttling: wait, send the same batch again
      Reconnect(String), // connection lost: connect again, then the same batch
      Fatal(String),     // auth, schema, a refused row: the link stops with `error` until a change
  }
  ```

  The network is the portable host's TCP/TLS (`tcp_connect`, `tls_connect`), the same in WASM and in a process. `SyncApp<T>` (crate `wyrm-history-sync`, done 2026-10-31) runs a target as an App: params `sink` (the sink's key), `batch` (≤ 5 000), `idle_s`, `retry_s`, the rest the target's; nodes `status`, `error`, `rows_sent`, `last_batch`, `cursor`; actions Set Password (the secret kept in the link's sealed store, never a param), Test Connection, Pause/Resume (kept across restarts). A link param holds no secret: the registry keeps params in the clear. Shared helpers serve families: `http` (HTTP/1.1 over `Net`: InfluxDB, DynamoDB), `sql` (a dialect: table definition, multi-row insert with the conflict clause, quoting: PostgreSQL, MySQL), `auth` (SCRAM-SHA-256 for PostgreSQL and MongoDB, SigV4). A family member then costs little: TimescaleDB speaks PostgreSQL, MariaDB speaks MySQL, QuestDB and VictoriaMetrics take InfluxDB line protocol. A new target is one crate: the trait, its `Params`, `export!`, package metadata. Not in the trait, unlike DSA: `query`/`queryFirst`/`queryLast` (reads stay on the edge historian; a read-back from the central database would add an optional method that answers `not_supported` by default) and `deleteRange` (the central database keeps its own retention, DynamoDB by TTL).
- **Host: TLS for portable Apps.** `Host::tls_connect(host, port, timeout_ms, ca_pem)` (and the same on `Services`): the host resolves the name on a thread of its own within the call's time, connects to the first address `NetPolicy::allows_named` accepts (an IP entry, or a listed name `db.example.com:5432` / `*.example.com:443` resolving to an ordinary address: a name never reaches loopback, link-local or metadata addresses by itself), and verifies the certificate for `host` against the system roots, or only against `ca_pem`, with rustls (ring) that `wyrmd` already links. The connection then takes `tcp_send`/`tcp_recv`/`tcp_close` like a plain one; the keys never leave the host. `Host::tls_upgrade(conn, host, timeout_ms, ca_pem)` starts TLS on an open plain connection (PostgreSQL and MySQL ask for TLS in band, `SSLRequest`), and `tcp_connect` takes a listed host name too, under the same rule. Done 2026-10-31 in the native host (`wyrm-link-portable`), so the native and process forms have it. The WIT import `tls-connect` comes with the next `wyrm:app` world version: `wyrm:app@0.2.0` is being defined on the DQL branch (ADR 0025 there), and two different 0.2.0 worlds must not exist; until then a WASM component gets `not_supported`.

| Target | Protocol | TLS | Idempotent write | Our client covers |
|---|---|---|---|---|
| InfluxDB (v2, v3) | HTTP, line protocol | cloud: yes | same measurement, tags and time overwrite | HTTP/1.1 request and status only |
| PostgreSQL | v3 wire protocol (own), SCRAM-SHA-256, TLS by `SSLRequest` | usually | `INSERT … ON CONFLICT (key, t) DO UPDATE`, one `(key, t)` per statement | startup, auth, one multi-row insert per batch, ping |
| DynamoDB | HTTPS, JSON, SigV4, `BatchWriteItem` (25 items, 16 MiB) | always | partition key `site/key`, sort key `t`; TTL attribute as DSA | SigV4 signing, retry of `UnprocessedItems` |
| MySQL | wire protocol | usually | `INSERT IGNORE`, primary key `(site, key, t)` | handshake, `caching_sha2_password` over TLS only (no RSA exchange), multi-row insert, ping |
| MongoDB | OP_MSG, BSON (`bson` crate, builds for wasm32), SCRAM-SHA-256 | Atlas: always | unique index `(site, key, t)`, `insert` with `ordered: false`; time-series collection optional | `hello`, auth, insert, ping |

- **Order of work.** 1) journal, sinks and the feed in `wyrm-history` and the admin, with e2e (late row resent, resend after a lost reply, `keep_after_sync_days`); 2) `tls-connect` in world `wyrm:app`; 3) `wyrm-history-sync` and the InfluxDB and PostgreSQL packages; 4) DynamoDB, MySQL, MongoDB. Done 2026-10-31: 1 (journal, sinks, feed, purge rule); 2 in the native host (the WIT import waits for the next world version); 3 core (`wyrm-history-sync`), the sink grant for the link, InfluxDB and PostgreSQL (with `tls_upgrade` in the host). Open: 4 (DynamoDB, MySQL, MongoDB) and the WIT imports. Each client is tested against an in-crate fake server and, in an ignored e2e, against the real database in a container.

## Consequences
- The broker grows by the journal and the feed only; targets add nothing to sites that do not use them.
- Each row costs about 16 more bytes on disk (the journal entry).
- A sink that stops confirming keeps its unsent days on the edge until Retention Days or Auto Purge remove them; its `lag_rows` grows and `rows_dropped_unsent` counts what is lost.
- Adding the first sink starts deleting days older than 90 days once they are sent. A site that wants a longer local history sets `keep_after_sync_days` higher or empty.
- The central database keys rows by the point's full key (`wy/<site>/…`), so several sites can share one table without the prefixes DSA needs.

## Alternatives
- **A sink inside `wyrmd` for each database:** a new build and restart for each target, a larger binary everywhere (the owner's two objections).
- **Remote database as the primary store (as DSA):** the edge would read its own history over the WAN; offline sites lose Get History.
- **Delete each row once sent (as the DSA buffer):** possible as `keep_after_sync_days: 0`, not as the only mode, for the same reason.
- **A cursor on time instead of a journal:** misses late rows and rows written again.
- **Sinks read `~val?history=` per point:** one query per point per batch, no cursor, no confirmation.
- **TLS inside the component (rustls with RustCrypto):** about a megabyte per component, slower under the fuel limit, and every package would carry its own copy of the roots.

## Owner decisions
1. ~~Disk full with unsent rows~~ — decided 2026-10-31: delete the oldest data, sent or not; local work goes on while the cloud may be stopped.
2. ~~`keep_after_sync_days` default~~ — decided 2026-10-31: 90 days.
3. ~~What a sink takes~~ — decided 2026-10-31: a list of watch groups per sink, empty = all; e.g. InfluxDB takes `energy` and `diagnostics`, DynamoDB only `energy`.
