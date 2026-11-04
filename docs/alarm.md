# Alarms

The alarm link watches points of the tree and raises **alarm records**: a value out of
range, a boolean that says "fault", a device that stopped sending, a sample of bad quality. A
dataflow, the agent or a person can raise one too. People acknowledge records, add notes and
look back over a time range. The records live in the broker's own store and go to a central
database through the history sync links (MySQL, MongoDB, PostgreSQL, InfluxDB, DynamoDB) with
no new protocol. Design: ADR 0034 (the link), ADR 0023 (portable links), ADR 0026 (the sinks).

Code: `links/alarm` (`wyrm-link-alarm`, the link as a portable `App`).

## 1. Words

| Word | Meaning |
|---|---|
| **Class** | A group of watches and their records (`line1`, `comms`, `safety`), with its escalation times. |
| **Watch** | A source point (or a subtree) and an **algorithm** that says when it is in alarm. |
| **Record** | One alarm: the source, the class, the type, a message, when it was raised, when it went back to **normal**, when and by whom it was **acknowledged**, its notes. |
| **Active** | The record's condition still holds (no `normal` yet). |
| **Open** | Active, or not yet acknowledged. **Closed**: normal and acknowledged. |
| **Type** | `alert`, `warning` or `fault` (as DSA). |
| **Inhibit** | `to_alarm_s`: the condition must hold this long before a record is made; `to_normal_s`: it must be gone this long before the record is normal. |
| **Escalation** | A record nobody acknowledged within `escalation1_s` is at level 1, within `escalation2_s` at level 2. |
| **Sink** | A reader of the records for a central database: a history sync link that pulls batches with `next`. |

## 2. Where it runs

One source runs in three modes (ADR 0023). They behave the same.

| Mode | Where | How you get it |
|---|---|---|
| Embedded (the default) | `wy/<site>/downstream/alarm` | Every `wyrmd` runs it. `wyrmd.json5` `alarm: { enabled: true, store_mb: 64, retention_days: 365, max_records: 100000 }` (all optional). |
| WASM package | `wy/<site>/downstream/<id>` | Package `alarm` (a component), *Install Link ▸ from Repository / Zip / Url*. Store 16 MiB. |
| Process package | `wy/<site>/downstream/<id>` | Package `alarm-process`, the same app as a supervised process. Store 16 MiB. |

`examples/packages/build.sh` builds both packages.

- The id `alarm` belongs to the embedded instance (as `scheduler` and `dql`): a new link
  cannot take it, and `wyrmd` refuses to start with a stored link of that id.
- The embedded link reads this site's `downstream`, `dataflows` and `storage`. It writes
  nothing, so no link needs to trust its key.
- **Grants of a package.** A package has no grants of its own. Before a package can watch a
  point, give it `read` on that point's link: `sys/links/<id>` ▸ Grant Access
  `{path: wy/<site>/downstream/<link>, level: read}`. A watch added before the grant shows
  `error: permission_denied`; *Disable* and *Enable* it once the grant is there.
- **Params of a package:** `retention_days` (365, at most 3 650) and `max_records` (100 000,
  at most 1 000 000), beside the capabilities, with the link's `update`.

## 3. The tree

```
alarm/
  add_class {id, display?, escalation1_s?, escalation2_s?}          write
  raise {class, source, type?, message?} -> {id}                    write   a record no watch owns
  acknowledge {id, note?}   normal {id}   add_note {id, note}       write
  ack_all {class?} -> {acknowledged}                                write
  get_alarm {id} -> the record;  get_notes {id} -> rows             read
  get_alarms {timerange?, class?, source?, state?, type?, limit?}   read    -> {rows, complete, scanned_to}
  import {json, overwrite?}   purge {before}                        config
  add_sink {name, link, classes?, from?}                            config
  stats/open, active, unacked, records, watches, raised, dropped
  sinks/<s>      value: the confirmed journal entry; attrs link, classes, lag_entries,
                 rows_sent, dropped_unsent, last_request; next (read), edit, reset, remove (config)
  <class>/       attrs display, escalation1_s, escalation2_s, created_by
                 add_watch (config); edit, remove, ack_all (write); export (read)
    open, active, unacked     counts
    alarms                    the open records, newest first, at most 200 rows
    watches/<w>  value: normal | alarm | to_alarm | to_normal | disabled | error
                 attrs source, algorithm, params, type, message, to_alarm_s, to_normal_s,
                 keys, in_alarm, last_change, last_record, error, created_by
                 edit, enable, disable, remove (config)
```

A record's `state` in answers: `active` (not normal, not acknowledged), `acked`
(acknowledged, still active), `normal` (normal, not acknowledged), `closed`.

## 4. Watches

`add_watch {source, algorithm, …}` on a class:

| `algorithm` | In alarm while … | Parameters |
|---|---|---|
| `boolean` | the value equals `alarm_value` (default `true`). A number counts as `true` when it is not 0; the texts `true`/`false`, `on`/`off` too. | `alarm_value` |
| `out_of_range` | the value is below `min` or above `max` (either may be absent). Back to normal only `deadband` inside the limit (hysteresis). A value that is not a number says nothing. | `min`, `max`, `deadband` |
| `staleness` | no sample came for `stale_s` seconds. The next sample ends it. | `stale_s` |
| `quality` | the sample's quality is `bad`; with `include_uncertain` also `uncertain`. | `include_uncertain` |

Through an action an enum is given by its index, as everywhere in WYRM (`algorithm`: 0
`boolean`, 1 `out_of_range`, 2 `staleness`, 3 `quality`; `type`: 0 `alert`, 1 `warning`, 2
`fault`; `get_alarms` `state`: 0 `open`, 1 `active`, 2 `unacked`, 3 `closed`, 4 `all`; a sink's
`from`: 0 `start`, 1 `now`); in an import, by its name.

Common fields: `type` (`alert`, `warning`, `fault`), `message` (a template:
`{name}` is the key's last segment, `{source}`, `{value}`, `{quality}`, `{class}`, `{watch}`,
`{stale_s}`; default `{name}: {value}`), `to_alarm_s`, `to_normal_s`, `enabled`.

- **Source:** a point key `wy/<site>/downstream/<link>/<path>` (also under `dataflows` or
  `storage`), or a subtree `wy/<site>/downstream/<link>/**`: one subscription, one state per
  key, one record per key (at most 2 000 keys; beyond, the watch shows `error`). `keys` and
  `in_alarm` count them.
- **One record per key at a time:** while a key's record is active, the same condition
  makes no second one; after it is normal, the next alarm is a new record.
- **Inhibits** are measured on the broker's clock from the sample's arrival. A flip of the
  condition before the time is up cancels the wait. They do not apply to `staleness`.
- **Who may add a watch:** `add_watch` is `config` (it subscribes a point), and the watch
  keeps its author's rights (ADR 0029): a token without `auth` (a dataflow's) cannot add
  one; a source the author may not `read` is refused; a subtree watch drops the keys its
  author may not read. The watch keeps running after its author loses rights. A watch edited
  with a new `source` takes the editor's rights.
- **Disable, remove, a new source:** the watch's active records go back to normal (nobody
  watches them any more).

## 5. Records

- `raise {class, source, type?, message?}` makes a record no watch owns: a dataflow's
  `invoke` sink, the agent or a person says there is a problem with `source` (a key of this
  site). `normal {id}` ends it; a watch's record ends by its point. `raise` needs `write` on the
  link and no `auth`.
- `acknowledge {id, note?}` names the caller (`ack_by`) and the time; `add_note {id, note}`
  (≤ 20 notes of ≤ 1 KiB per record, also on a closed one); `ack_all {class?}` acknowledges
  every open record the caller may see.
- **Who sees what:** `get_alarms`, `get_alarm`, `get_notes`, `acknowledge`, `normal`,
  `add_note` and `ack_all` need the caller's `auth` (the gateway, `wyr` and the agent give it)
  and answer only records whose `source` the caller may `read`. A class's `alarms` table and
  the counts are for whoever may read those nodes: a role with `read` on the alarm link reads
  the site's alarms.
- `get_alarms`: `state` is `open` (default), `active`, `unacked`, `closed` or `all`;
  `timerange` `<from>/<to>` (RFC 3339, on the creation time); `class`; `source` (a key, or a
  prefix ending with `/`); `type`; `limit` (500, ≤ 5 000). Rows come newest first. The open
  records are in memory; `closed` and `all` read the store, at most 256 pages (16 384 records)
  per call: `complete: false` and `scanned_to` (the oldest creation time read) say where to
  go on with a narrower `timerange`.
- **Escalation:** a record nobody acknowledged within the class's `escalation1_s` goes to
  level 1 (`escalation`), within `escalation2_s` to level 2; each is a change the sinks see.
- **Bounds:** 10 000 open records; over it the oldest record that is normal but
  unacknowledged is acknowledged by `system:overflow` (a storm cannot grow without end). With
  none such (all active) the record is still made. 200 classes, 500 watches per class, 1 000 in
  all.

## 6. The store, retention and restarts

Records live in pages of 64 in the link's sealed store (`p/<n>`), the open ones also in
memory; every creation and change is one entry of a **journal** (`j/<n>`, at most 102 400
entries) that sinks read. A record is on disk before the action that made it answers; a
record made from a sample is logged at `error` and counted in `stats/dropped` when the store
refuses it.

- **Retention:** once a day (and at start) the oldest pages whose records are all closed go
  while they are older than `retention_days` or the store holds more than `max_records`. A page
  with an open record stays: an open alarm is never deleted. `purge {before}` (config) removes
  the closed records created before an instant, page by page.
- **Restart:** the classes and watches come back, the open records too. A watch's key whose
  record is active starts as "record open": the first normal sample closes it, the same alarm
  makes no second record. A `staleness` watch counts from the start. Escalations due are
  still due.
- **Clock steps:** inhibits, staleness and escalations are durations; a wall-clock step (NTP,
  a resume from sleep) moves them with it. A step seen by a timer is exact; one seen by another
  event first is measured against the link's last event, so a wait may end late by that much
  (at most the 30 s watchdog).

## 7. Sinks: records in a central database

The records go out through the **history sync links** (ADR 0026), exactly as the historian's
rows do. On the alarm link: `add_sink {name, link, classes?, from}` — the link id that reads it,
the classes it takes (empty: all), and whether it starts from the oldest journal entry kept
(`start`) or from now. Then on the sync link (installed from its package: `postgres`, `mysql`,
`mongodb`, `influxdb`, `dynamodb`, or their `-process` forms) set the param
`sink: wy/<site>/downstream/alarm/sinks/<name>` beside its own params, and give it
`read` on the sink's key: `sys/links/<db link>` ▸ Grant Access
`{path: wy/<site>/downstream/alarm/sinks/<name>, level: read}`. Use a table, measurement or
collection of its own for alarms.

Each row the database gets is one record: `key` = the record's source point, `t` = when it was
raised, `v` = the record as JSON text (`wyrm-alarm/1`: `id`, `class`, `watch`, `source`,
`type`, `message`, `value`, `created`, `normal`, `ack`, `ack_by`, `escalation`, `notes`,
`by`, `state`), `q` = good. Every change (normal, acknowledged, a note, an escalation) sends the
record again with the same `(key, t)`, so the database holds its last state (PostgreSQL and
MySQL replace on their primary key, MongoDB on `_id`, DynamoDB on its keys, InfluxDB on the same
series and time). In PostgreSQL `value_text::jsonb` queries the fields.

Only the sink's link may call `next` (it signs as `link:<id>`); anyone else is refused, since
`next` confirms the previous batch. The sink node shows `lag_entries` (changes not yet
confirmed), `rows_sent` and `dropped_unsent` (journal entries that went before the link
confirmed them: the journal keeps the last 102 400 changes). `reset {from}` moves the cursor.

## 8. Example: a PLC's faults, to PostgreSQL

```
alarm ▸ Add Class {id: line1, escalation1_s: 600, escalation2_s: 3600}
alarm/line1 ▸ Add Watch {source: wy/plant/downstream/plc1/line1/ahu1/fault,
                         algorithm: boolean, type: fault, message: "AHU1 fault"}
alarm/line1 ▸ Add Watch {source: wy/plant/downstream/plc1/line1/ahu1/temp,
                         algorithm: out_of_range, max: 28, deadband: 1,
                         to_alarm_s: 60, type: warning, message: "{name} at {value} °C"}
alarm/line1 ▸ Add Watch {source: wy/plant/downstream/plc1/**, algorithm: quality,
                         to_alarm_s: 30, message: "{source}: {quality}"}
alarm ▸ Add Sink {name: cloud, link: pg, from: start}
sys/links/pg ▸ Grant Access {path: wy/plant/downstream/alarm/sinks/cloud, level: read}
(on pg: params sink = wy/plant/downstream/alarm/sinks/cloud, table = alarms)
```

The explorer shows `line1/alarms` as a table; `get_alarms {state: closed, timerange: …}` looks
back. With `wyrm-agent` (ADR 0033): `invoke wy/plant/downstream/alarm get_alarms
'{"class":"line1"}'`.

## 9. What differs from the DSA alarm link

Kept: classes, watches with Boolean, Out Of Range and Staleness algorithms (and `quality`,
new), the three types, the record's life and notes, escalations, Get Alarms over a range,
acknowledge all, a database behind. Changed: the records are in the broker's sealed store,
not in a database inside the link; the central database is fed through the sync links the
site already uses, not by swapping the record store; nothing polls (a change is one journal
entry, a quiet site sends nothing); every bound is explicit; whoever acknowledges or reads
must be able to read the source point, and a watch reads with its author's rights.
