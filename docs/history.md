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

Broker storage (`wy/<site>/storage`, values that people create) is kept in
`data_dir/storage/storage.redb`. To change a storage value in the explorer,
click it in Metrics and type the new value:

| Type | Type it as | Example |
|---|---|---|
| `number` | a number; a unit after it is ignored | `21.5` |
| `bool` | choose `true` or `false` | |
| `string` | text | `north wing` |
| `map` | a JSON object | `{"mode": "eco", "limit": 40}` |
| `array` | a JSON array | `[1, 2, 3]` |
| `binary` | hex bytes, `0x` before them is optional | `0x0a1b` |
| `dynamic` | JSON, or else text | `{"on": true}` or `hello` |

The explorer does not send text that is not of the value's type. It shows
why under the value, for example "a JSON object".

## 2. Record history

Open `wy/<site>/sys/history`.

1. ▸ **Add Watch Group**: Name, Logging Type, Interval, Buffer Flush Time.
2. Open the group ▸ **Add Watch Path**: Path. Write `downstream/<link>/<point>`
   (this site), or the full key `wy/<site>/downstream/…` (this site or a
   downstream site). Flow outputs (`dataflows/<flow>/…`) work too.
3. The watch appears as `w1`, `w2`, … with the point key as its name.
4. The point itself shows that it is recorded: its `~meta` gets
   `attr.history` (the watch keys), its row in the tree and in Metrics a
   history mark; a click on the mark opens its history (ADR 0016). A
   downstream site's point recorded here gets the mark as seen through
   this site's gateway (`sys/overlays/.sites`, ADR 0020), not on the
   downstream site itself.

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
| Explorer | the history mark after a recorded point's name, or right-click a recorded point (in Data or Metrics; `attr.history`, as DSA's `@@getHistory`) ▸ **View History**: presets 1 h, 24 h, 7 d, 30 d, or From/To, Interval, Rollup ▸ Load; a chart of the numeric values (bad samples as red dots) and the rows; the store that records it at the top (a choice when there are several) |
| Zenoh | `get wy/<site>/downstream/<link>/<point>/~val?history=2026-10-22T08:00:00Z..&agg=avg&window=5m` (spec 01/03): one or more replies, each a CBOR array of `[t, v, q]` (or `[t_start, v]`) |
| Rust | `WyrmClient::history(node, &HistoryQuery { from, to, agg, window, limit })` |
| Dart | `api.history(key, from: …, to: …, agg: …, window: …)` (gateway and FFI) |
| CLI | `wyr values wy/<site>/downstream/mock/g0/p0 --from 2026-10-22 --agg avg --window 1h` |
| Gateway WS | op `history`, `args {from, to, agg, window, limit}`; needs `read` on the point |

- Parameters: `history=<from>..<to>` (an empty end is now) or `since=<from>`;
  `agg` and `window` as Rollup and Interval above; `limit` rows (10 000 by
  default, at most 100 000).
- This site's broker answers for its points; a downstream site's broker
  answers for the points it records.
- Every watch also answers at its own key
  (`wy/<site>/sys/history/<group>/<watch>/~val?history=`): that is where a
  downstream site's point recorded here is read (ADR 0020). Through the
  gateway it needs read on the point itself.
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
| `keep_after_sync_days` | 90 | With at least one sink (section 6): delete a day once every sink confirmed it and it is older than this; 0 keeps only what is not sent; empty: off. |

- The current day is never deleted by these rules.
- `retention_days` and `auto_purge` never wait for a sink: the equipment
  keeps recording while the cloud may be down. Rows a sink had not confirmed
  are counted in its `rows_dropped_unsent`.
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
| Sinks | 16; a batch at most 5 000 rows and 1 MiB |

## 6. Sending the history on: sinks (ADR 0026)

A sink lets one link read what the historian writes, in batches, and send it
on to another database (InfluxDB, PostgreSQL, MySQL, MongoDB, DynamoDB). The
historian stays the store on the site; only it deletes.

1. Install the link that sends the rows.
2. On `sys/history/sinks` ▸ **Add Sink** {Name, Link, Groups, From}: the
   watch groups it takes, comma separated (empty: all); From `start` sends
   everything on disk, `now` only what is written from now on. The link gets
   a requester key and, if it runs as a process, starts again; the broker
   rebuilds once.
3. The link asks ▸ **Next Batch** {After, Max} on its sink and gets
   `{rows: [{seq, key, t, v, q}], next}`; it stores the rows, then asks again
   with `after` = `next`. That `after` confirms every row up to it (at least
   once: a lost reply sends the batch again, so the database must replace on
   `(key, t)`). At most 5 000 rows and 1 MiB per batch.

Only the sink's link may ask (it signs as `link:<id>`); a person who ran
Next Batch would confirm rows the database never got, so it is refused.
A sink shows `link`, `groups`, `confirmed_seq`, `lag_entries` (journal
entries after the cursor; rows of other groups count too), `rows_sent`,
`rows_dropped_unsent` and `last_request`; actions Edit, Reset Cursor {start |
now} and Remove. Every row written gets a journal number, so a late row or a
row written again is sent again. Rows recorded before this version have no
number and are not sent.

### Sink links

Each database is a link package of its own (ADR 0026), built on
`wyrm-history-sync`: a WASM package by default, a process package from the
same code. Install it, then:

1. Give it the params: `sink` (the sink's key, `wy/<site>/sys/history/sinks/<name>`:
   Copy Path on the sink), `batch` (rows per batch, default 500, at most 5 000),
   `idle_s` (wait when nothing is new, default 5), `retry_s` (longest wait after
   an error, default 60), and the database's own params (below). Put the
   database's host in the link's `net` list (a host name is allowed for TLS:
   `db.example.com:443`). A WASM package reaches TLS only when it is built for
   the world `wyrm:app@0.3.0` (every `wyr link pack` since 2026-11-01, ADR
   0030); one built for 0.2.0 answers `not_supported` to TLS: rebuild it or
   use the process package.
2. ▸ **Set Password**: the password or token, kept in the link's sealed store
   (never a param: the registry keeps params in the clear).
3. Add the sink for this link (section above), then ▸ **Test Connection**.

The link shows `status` (connecting, reading, idle, waiting after an error,
failed, paused), `error`, `rows_sent`, `last_batch` and `cursor`; ▸ Pause and
▸ Resume (kept across restarts). A failed link (wrong token, a refused row)
waits for a change: Set Password, Resume or new params.

| Link | Params | Writes |
|---|---|---|
| `influxdb` | `url` (`https://host[:port][/base]`; `http://` only to loopback unless `insecure_plaintext`), `org`, `bucket`, `measurement` (default `wyrm`), `ca_pem`, `timeout_ms` | v2 write API (InfluxDB 2.x and 3.x), line protocol at µs: tags `site`, `key`; fields `value`, `quality`. A row that is not a number, a bool or text is skipped. |

| `postgres` | `host`, `port` (5432), `database`, `user`, `table` (`wyrm_history` or `schema.table`), `sslmode` (`require`, default, or `disable`: loopback only unless `insecure_plaintext`), `ca_pem`, `timeout_ms`, `create_table` (true) | One table `site, key, t timestamptz, value double precision, value_text text, quality smallint`, primary key `(key, t)`, upsert. TLS by `SSLRequest`; SCRAM-SHA-256, or a cleartext password over TLS or to loopback; MD5 is refused. TimescaleDB too (make the table a hypertable yourself). |

| `dynamodb` | `region`, `table`, `access_key_id`, `endpoint` (default the region's; `http://` only to loopback, for DynamoDB Local, unless `insecure_plaintext`), `ttl_days` (0: none), `create_table` (false), `ca_pem`, `timeout_ms` | BatchWriteItem, 25 puts per request, SigV4; partition key `key`, sort key `t` (µs), `site`, `value` (N, BOOL, S or NULL), `quality`, `expiration` (epoch s) with `ttl_days`: switch the table's TTL on in AWS. The secret access key with Set Password. |

| `mysql` | `host`, `port` (3306), `database`, `user`, `table` (`wyrm_history`), `ssl` (`require`, default, or `disable`: loopback only unless `insecure_plaintext`), `ca_pem`, `timeout_ms`, `create_table` (true) | MySQL and MariaDB. One table `` site, `key` VARCHAR(700), t DATETIME(6), value DOUBLE, value_text TEXT, quality `` (utf8mb4), primary key `` (`key`, t) ``, `INSERT … ON DUPLICATE KEY UPDATE`; text as hex literals. TLS by `SSLRequest`; `caching_sha2_password` (the full login only over TLS: no RSA) or `mysql_native_password`. A key over 700 characters is skipped. |

| `mongodb` | `host` (the primary or a mongos; `mongodb+srv` is not resolved), `port` (27017), `database`, `collection` (`wyrm_history`), `user`, `auth_source` (`admin`), `tls` (true; false only to loopback unless `insecure_plaintext`), `ca_pem`, `timeout_ms`, `ttl_days` (0: no TTL index) | OP_MSG; one document per row, `_id: {k, t}`, with `site`, `key`, `t` (µs), `ts` (a date), `value`, `quality`; a batch is one `update` of replace-upserts, `ordered: false`. SCRAM-SHA-256 (an ASCII password: it is not SASLprep-normalised). With `ttl_days`, a TTL index on `ts`. |

## 7. Other historians

A link can record history itself (another database, a cloud service): give
it a `read` grant on the points (`requester` in its package, or `sys/links/<id>`
▸ Grant Access, ADR 0013). `examples/links/requester` records
`wy/<site>/downstream/mock` to a CSV file this way.

## 8. Not yet

- A watch for a whole subtree (`downstream/<link>/**`): today one watch is one
  point.
- MCP tool `history` (`tools/wyrm-mcp`).
