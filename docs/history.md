# Data storage and history

This page tells you where WYRM keeps point values, how to record history in
the broker, how to read it back, and what the limits are. Decision: ADR 0014.

## 1. What the broker keeps

| What | Where | How long | Who reads it |
|---|---|---|---|
| The **last value** of every point (`wy/**/~val`) | Zenoh storage, `memory` volume, in RAM | until the broker stops | every `subscribe` (the stored value first, then live), `get ~val` |
| **History** of the points you watch | `data_dir/history`, one file per UTC day | until `retention_days` or `auto_purge` deletes the day | `sys/history/<group>/<watch>` ▸ Get History |
| Control-plane state (links, ACL, flows, settings) | `data_dir/state` (WAL + snapshot) | always | the admin |

The last values are not saved: after a restart a point has a value again when
its link publishes one. History is recorded only for points in a watch group.

## 2. Record history

Open `wy/<site>/sys/history`.

1. ▸ **Add Watch Group**: Name, Logging Type, Interval, Buffer Flush Time.
2. Open the group ▸ **Add Watch Path**: Path. Write `down/<link>/<point>`
   (this site), or the full key `wy/<site>/down/…` (this site or a
   downstream site). Flow outputs (`flows/<flow>/…`) work too.
3. The watch appears as `w1`, `w2`, … with the point key as its name.

| Logging Type | Records |
|---|---|
| None | nothing (the group is paused) |
| Interval | the last value of each point every Interval seconds, changed or not |
| All Data | every update |
| Point Change | an update whose value or quality differs from the last one recorded |

- **Buffer Flush Time** (seconds, 0.1 to 600): rows wait in memory, then go
  to disk in one write. A longer time writes less often; a crash loses the
  rows in memory.
- **Interval** (seconds, 0.1 to 86 400): Interval logging only.
- Change them with the group's ▸ **Edit**. A watch's `enabled` pauses one
  point.
- After a restart or a router rebuild the group goes on; the first value it
  sees is not stored again if it is the one already stored.

## 3. Read history

The watch ▸ **Get History** (needs `config` on `sys/**`, as every action
here: the rows are point values):

| Field | Meaning |
|---|---|
| Timerange | `<from>/<to>` in RFC 3339: `2026-10-22T08:00:00Z/2026-10-22T12:00:00Z`. A date alone is its midnight UTC; an offset (`+03:00`) is allowed; an empty end is now: `2026-10-22/`. |
| Interval | `none`, or a number and `s`, `m`, `h`, `d`, `w`: `5m`, `1h`, `1d`. One row per interval, starting at `from`. |
| Rollup | how the samples of one interval become one value: `none` (the first), `first`, `last`, `avg`, `min`, `max`, `sum`, `count`, `delta` (last − first), `and`, `or` (booleans). A Rollup without an Interval gives one row for the whole range. |
| Rows | at most this many rows: 1 000 by default, at most 10 000. |

The answer is a table (in the explorer: output ▸ **Table..**):

- raw rows: `time`, `value`, `quality` (`good`, `uncertain`, `bad`);
- with an Interval or a Rollup: `time` (the interval start) and `value`.
  Rollups skip `bad` samples; intervals without samples give no row.

Each watch also shows `start_date` and `end_date`. It does not show
its last value (DSA's Last Written Value): the point itself has it.

### Without `sys`: the point's own history

Everyone who may read a point's value may read its history; no `sys` rights
are needed (spec 05 0.1.10):

| Where | How |
|---|---|
| Explorer | right-click a point (in Data or Metrics) ▸ **View History**: presets 1 h, 24 h, 7 d, 30 d, or From/To, Interval, Rollup ▸ Load; a chart of the numeric values (bad samples as red dots) and the rows |
| Zenoh | `get wy/<site>/down/<link>/<point>/~val?history=2026-10-22T08:00:00Z..&agg=avg&window=5m` (spec 01/03): one or more replies, each a CBOR array of `[t, v, q]` (or `[t_start, v]`) |
| Rust | `WyrmClient::history(node, &HistoryQuery { from, to, agg, window, limit })` |
| Dart | `api.history(key, from: …, to: …, agg: …, window: …)` (gateway and FFI) |
| CLI | `wyr values wy/<site>/down/mock/g0/p0 --from 2026-10-22 --agg avg --window 1h` |
| Gateway WS | op `history`, `args {from, to, agg, window, limit}`; needs `read` on the point |

- Parameters: `history=<from>..<to>` (an empty end is now) or `since=<from>`;
  `agg` and `window` as Rollup and Interval above; `limit` rows (10 000 by
  default, at most 100 000).
- This site's broker answers for its points; a downstream site's broker
  answers for the points it records.
- A point nobody records has no history: the answer is empty. A wrong
  parameter or a wildcard in the key is an error.

## 4. Space and purging

`sys/history` shows `rows_written`, `writes_per_second`, `rows_pending`,
`rows_dropped`, `last_flush`, `database_size`, `space_available`, `series`,
`day_files` and `oldest_day`. A group shows its `logging_type`, `interval`
and `buffer_flush_time`.

| Setting | Default | Effect |
|---|---|---|
| `auto_purge` | on | Every minute: while the disk has less free space than `disk_space_remaining`, delete the oldest day. |
| `disk_space_remaining` | 1024 MiB | The free space `auto_purge` keeps. |
| `retention_days` | 0 (keep) | Every minute: delete days older than this. |

- The current day is never deleted by these two.
- ▸ **Purge** {Timerange} on `sys/history` deletes every point's rows in the
  range; on a watch, that point's rows only.
- ▸ **Unsubscribe** stops recording a point and keeps its rows; ▸
  **Unsubscribe and Purge** deletes them too. A group's ▸ **Delete** with
  Purge deletes the rows of all its watches.
- Every change, purge and automatic deletion is in the audit journal
  (`history_group`, `history_watch`, `history_options`, `history_purge`).

## 5. Limits

| What | Limit |
|---|---|
| Watch groups | 64 |
| Watches | 10 000 in all, one point each (no wildcards), never `sys` |
| Rows in memory | 200 000 for all groups; more are dropped (Rows Dropped) |
| Sample time | the source's time; more than 5 min ahead of the broker's clock or more than 31 days back: dropped (Rows Dropped) |
| Get History | 10 000 rows per call (`~val?history=`: 100 000) |
| One read | at most 5 000 000 rows scanned (a longer range is refused: ask for a shorter one); 4 reads at a time, others wait up to 5 s |
| Gap at a router rebuild | about a second: samples then are not recorded |

## 6. Other historians

A link can record history itself (another database, a cloud service): give
it a `read` grant on the points (`requester` in its package, or `sys/links/<id>`
▸ Grant Access, ADR 0013). `examples/links/requester` records
`wy/<site>/down/mock` to a CSV file this way.

## 7. Not yet

- A watch for a whole subtree (`down/<link>/**`): today one watch is one
  point.
- MCP tool `history` (`tools/wyrm-mcp`).
