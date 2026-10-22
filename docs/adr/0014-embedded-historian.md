# ADR 0014 — Embedded historian (`sys/history`)

**Status:** accepted (owner decision 2026-10-22: the history store is built into the broker, with statistics and actions in `sys`, as DSA's etsdb link; other historians stay possible as requester links). The store engine (redb, one file per day) is a proposal the owner can change. · 2026-10-22

## Context
- Zenoh's storage manager keeps `wy/**/~val` in the `memory` volume: the last value of each point, in RAM, lost on restart. It keeps no history.
- Zenoh volumes that persist or keep history (rocksdb, filesystem, influxdb) load only as dynamic `.so` plugins, which principle 2 forbids. Of them only influxdb keeps more than the last value, and it needs an external server.
- Spec 01/03/05 already define the read side: `get <point>/~val?history=<from>..<to>[&agg=&window=]` → CBOR array of `[t, v, q]`.
- The owner wants the historian of the DSA etsdb link (its nodes and functions, not its database) in the broker, and external historians as links that read through requester grants (ADR 0013; example `examples/links/requester`).

## Decision
- **Crate `wyrm-history`**: the store, the watch-group engine and the query folder. The admin hosts its nodes under `wy/<site>/sys/history`; its settings are control-plane state in the registry (`Registry::historian`, ops `PutWatchGroup`, `RemoveWatchGroup`, `AddWatch`, `SetWatchEnabled`, `RemoveWatch`, `SetHistoryOptions`, SCHEMA 12).
- **Store: redb** (pure Rust, ACID, no C/C++ toolchain; `~4.1`, the newest line for MSRV 1.89), **one file per UTC day** in `data_dir/history/days/YYYY-MM-DD.redb`, plus `index.redb` (point key → series number). Row key `(series u32, t µs)`, value canonical CBOR `[v, q]`; a row with the same key replaces the old one. A day is the unit of retention: redb reuses freed pages but never shrinks a file, so purging by whole files is what gives the disk its space back. Page cache 8 MiB per file, at most 4 files open.
- **Engine** (DSA historian): watch groups with `Logging Type` None / Interval (the last value every `interval`, changed or not) / All Data (every update) / Point Change (value or quality changed), and `Buffer Flush Time` (rows wait in memory, then one transaction per day file). A watch follows `<key>/~val` on the broker's in-process session with `wyrm-client`'s `subscribe` (stored value first, then live). All Data and Point Change compare with the last stored row, so a restart or a router rebuild does not store the initial value twice. Pending rows are capped at 200 000 for all groups; more are dropped and counted.
- **Rebuilds** (ADR 0006): the historian lives in `Control` and outlives a router rebuild; `attach` binds it to each new session, `detach` flushes the buffers before the old one closes. Samples published during the rebuild gap (about a second) are not recorded.
- **Watch paths**: one point each, `wy/<site>/down/<link>/…` or `wy/<site>/flows/<flow>/…` of this site or of a downstream site (its data arrives over the peer link); never `sys`, no wildcards. At most 64 groups and 10 000 watches.
- **Nodes** (lowercase keys, DSA display names):
  - `sys/history`: Rows Written, Writes Per Second, Rows Pending, Rows Dropped, Last Flush Duration, Database Size, Space Available, Series, Day Files, Oldest Day; writable Auto Purge (default on), Disk Space Remaining (MiB, default 1024), Retention Days (default 0 = keep); actions Add Watch Group, Purge {Timerange}.
  - `sys/history/<group>`: Logging Type, Interval, Buffer Flush Time; actions Edit, Add Watch Path {Path}, Delete {Purge}.
  - `sys/history/<group>/w<N>` (display = the point key): Enabled (writable), Start Date, End Date; actions Get History {Timerange, Interval, Rollup, Rows}, Purge {Timerange}, Unsubscribe, Unsubscribe and Purge. No Last Written Value (DSA has one): `sys` would republish point values to everyone who may read `sys`.
- **Get History** answers a table (array of records): raw rows `{time, value, quality}`; with an Interval or a Rollup one row per interval `{time, value}` (interval start, aligned to the range start). Rollups: none (first), and, or, avg, min, max, sum, first, last, count, delta; they skip `bad` samples. Timerange `<from>/<to>` (DSA) or `<from>..<to>` (spec 01), RFC 3339, empty end = now. At most 10 000 rows (1 000 by default).
- **Purging**: every minute, days older than Retention Days go, then, with Auto Purge, the oldest days while the disk has less free space than Disk Space Remaining. The current day is never deleted. Each deletion is logged and audited (`history_purge`); so are the Purge actions and every settings change (`history_group`, `history_watch`, `history_options`).
- **Access**: every action, Get History included, needs `config` on `sys/**`: the rows are point values, and a role with `read` on `sys` need not have `read` on the points. Through the gateway only the `admin` role reaches `sys/**` (ADR 0009). Reading history with the rights of the point itself comes with `~val?history=` on the point's own key (D2).

## Consequences
- Principle 3 ("the broker owns only itself") gets one exception: the broker keeps time series of points it watches, by the owner's decision. The node tree and the last values are still owned by links and the memory storage.
- `data_dir/history` grows with the watches; Auto Purge and Retention Days bound it. It is not HMAC-protected like the registry (it is data, not control state); `wyrmd verify` does not check it.
- The spec read path `~val?history=` is not served yet: it needs a queryable beside the memory storage (two answers per query, the client keeps the array) and a decision on spec 05's `history:read` token. Planned with the explorer's history view (D2).
- The CLAUDE.md layout named `history/{rocksdb,influxdb}` as `HistoryStore` backends. RocksDB would bring a C++ build into every cross-compile for the ARM boards; InfluxDB is an external server and fits better as a requester link.

## Alternatives
- **Zenoh storage volumes** (rocksdb, influxdb): dynamic plugins only (principle 2); rocksdb keeps the last value only.
- **One redb file for everything**: simpler, but purging would not give the disk space back without a compaction that needs the space it frees.
- **Own append-only files per day** (as etsdb): no index per series, so reading one point scans all points of a day.
- **fjall** (LSM, pure Rust): younger; compaction runs in the background on the reference board.
- **External historian only** (a requester link): kept as an option (the recorder example), but the owner wants one in the broker.
