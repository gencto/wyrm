# ADR 0034 — Alarm link: broker-side alarms, records that survive, export through the history sync links

**Status:** accepted · 2026-11-04, built (owner request: an alarm link for the broker, better than the DSA reference in performance and in how it keeps its data; keep the records in the broker's own store, send them on through the database links that exist already; run in every mode as the scheduler does). Built as a portable `App` (ADR 0023): `links/alarm`; user guide `docs/alarm.md`.

## Context
Sites need alarms on the broker: a point out of range, a boolean that says "fault", a device that stopped sending, a sample of bad quality. People acknowledge them, add notes and look back over a time range; a central database wants the same records. The owner's reference is DSA `dslink-java-alarm` (IOT-DSA, read 2026-11-04). Kept from it: alarm classes; watches on source points with an algorithm (Boolean, Out Of Range, Staleness) that creates an alarm record; alarm types `alert`, `warning`, `fault`; a record's life — created, back to normal, acknowledged (by whom and when), closed when both; inhibit times before an alarm and before a return to normal; two escalation levels on records nobody acknowledged; notes on records; Get Alarms over a time range, open alarms, acknowledge all; an alarm database with providers. Not kept, because they are its defects (read in the source):
- the records live in a database inside the link (H2 or another JDBC database through a provider), a second store beside the broker's own, with its own files, locks and upgrades; sending records to a central database means swapping that provider, so the local copy is gone;
- the alarm streams (open alarms, escalations, return to normal) poll the database every few seconds for every client holding them, so the load grows with clients and never reaches zero at idle;
- staleness is a timer per watch and the escalations a sweep of every open record, both on their own threads;
- the watches and classes are node configs written back to `nodes.json` by the SDK's periodic save, so an edit can be lost by a crash in the minute after it;
- nothing is bounded: open records, the rows of Get Alarms, the records a class holds in memory;
- anyone who reaches the link acknowledges any record; nothing of the caller's rights on the source point is checked.

What WYRM has that the link can use: a portable `App` with a sealed host store that survives restarts (ADR 0023), one subscription for a whole subtree (`<prefix>/**`, ADR 0025), the caller's rights in the token of an action (`auth`, spec 04 0.2.10, ADR 0029), and five history sync links that pull rows from a sink with `next {after, max}` and write them, replacing on `(key, t)`, to MySQL, MongoDB, PostgreSQL, InfluxDB and DynamoDB (ADR 0026).

## Goals
1. An alarm comes from the live tree (a watch's condition) or from a caller (`raise`: a dataflow's `invoke` sink, the agent, a person); the record is on disk before the event that made it ends.
2. After a restart the state follows from the records and the first samples: an open record stays open, a watched point that is normal on its first sample closes it; nothing missed is replayed.
3. Bounded: nodes, subscriptions, open records, records on disk, rows per answer, work per event; zero messages at idle.
4. Records go to a central database through the history sync links as they are, with no new protocol: the alarm link is a sink with the same `next` as the historian's.
5. A watch sees only what its author may read; a reader sees only the records of sources they may read; every acknowledgement names its subject.
6. One core in three modes (embedded, process, WASM), as the scheduler.

## Non-goals
- Alarm routing to e-mail, SMS, chat: a later link or a dataflow on the class's `alarms` table.
- Expressions as conditions (CEL as in DQL): later; the four algorithms cover the DSA link.
- Records as nodes: thousands of records would exhaust the node budget; they are rows of actions and of one table value per class.

## Anti-goals (a failure even if it works)
- A record accepted and lost (a crash after the reply, a store that refused the write unnoticed).
- A storm of alarms (a PLC off: every point bad) that stalls the link or the router.
- A reader who may not read a point learning its alarms.

## Decision

### Model (crate `links/alarm`, an `App` on `wyrm-link-api`; no clock, no I/O of its own)
- **Class:** `id` (key segment), `display`, `escalation1_s`, `escalation2_s` (0 = off), `created_by`, its watches.
- **Watch:** `id` (`w<n>`, never reused), `source` (a key `wy/<site>/<section>/…`, or `<prefix>/**` for every value under it), `algorithm`, its parameters, `type` (`alert | warning | fault`), `message` (a template: `{source}`, `{name}`, `{value}`, `{quality}`), `to_alarm_s`, `to_normal_s`, `enabled`, `created_by`, the author's rights (`Rights`, ADR 0029).
- **Algorithms:**
  - `boolean`: in alarm while the value equals `alarm_value` (default `true`; a number is `true` when not 0, text `true`/`false`);
  - `out_of_range`: in alarm while the value is below `min` or above `max` (either may be absent); back to normal only inside by `deadband` (hysteresis; a value that is not a number is ignored);
  - `staleness`: in alarm when no sample came for `stale_s`; the next sample ends it;
  - `quality`: in alarm while the sample's quality is `bad`, or also `uncertain` with `include_uncertain`.
- **Record:** `id` (one counter for the link, never reused), `class`, `watch` (none for `raise`), `source`, `type`, `message`, `value` (the sample that raised it, scalars only), `created`, `normal`, `ack`, `ack_by`, `escalation` (0, 1, 2), `notes` (≤ 20 of ≤ 1 KiB, each with time and subject). **Open** = active (no `normal`) or unacknowledged; **closed** = both set. A watched point with an open active record raises no second one; after its record is normal, the next alarm is a new record (DSA's rule).
- **Inhibit:** a condition must hold `to_alarm_s` before a record is made and be gone `to_normal_s` before the record is normal; a flip in between cancels the wait. Instants come from the host's wall clock at the sample's arrival, not from the sample's `t` (links stamp samples on their own clocks).
- **Escalation:** a record unacknowledged `escalation1_s` after it was created is at level 1, `escalation2_s` after it at level 2 (a journal entry each, so sinks see it); an acknowledgement ends the wait.
- **Bounds (constants of `links/alarm::limits`, one place each, refused with `resource_exhausted` before the host would fail the event):** 9 500 nodes; 200 classes; 500 watches per class and 1 000 in all (one subscription each; a subtree watch keeps state for at most 2 000 keys, beyond which its node shows `error`); 10 000 open records (over it, the oldest record that is normal but unacknowledged is acknowledged by `system:overflow`, so a storm cannot grow without end; with none such, the record is still made: an active alarm is real); 800 commands and 500 ms of batched work per event, the rest in `0` ms timer events (ADR 0022 ruling 5); 5 000 rows per answer.

### Store (the host store, ADR 0023: at most 10 000 keys, 64 MiB embedded)
A record is not a key: a store of 10 000 keys cannot hold one per record, and a value of thousands of records cannot be rewritten on each change. So:
- `index`: the class ids; `c/<class>`: the class with its watches (CBOR), written in the event that accepts the edit.
- `p/<n>`: **page `n` of records**, ids `64n … 64n+63` (CBOR array). Ids grow with time, so a page is found by its ids and a time range by a binary search on the pages' first records (≤ 12 reads for 4 096 pages). A record changes (normal, acknowledged, a note, an escalation) by rewriting its page: a page is at most about 64 × 400 B.
- `open`: the ids of the open records (one array; at most 10 000 ids, so about 50 KiB), rewritten when a record opens or closes. At start the open records are read from it; closed records stay on disk only.
- `j/<n>`: **journal page `n`**, the ids of the records that changed, entry `seq = 256n + i` (CBOR array). Every creation and change appends one entry; sinks read from a cursor on `seq`. At most 400 pages (102 400 entries): older pages go, confirmed or not, and what a sink has not confirmed of them is counted on it (`dropped_unsent`), as the historian does (ADR 0026, owner decision 1). The journal is written whether a sink exists or not, so a sink added later (`from: start`) takes the records of the last 102 400 changes.
- `sinks`: the sink definitions with their cursors (one map; a cursor moves with every batch).
- `meta`: `first_page`, `first_jpage` (the oldest pages kept) and `page_hint`, `jpage_hint` (the newest pages made, written when a page begins); the next record id and journal number follow from the last page after each hint (pages are contiguous), so `meta` is not written per record and a crash between a page and `meta` loses nothing. After a purge of every page the ids go on after the pages that went (`first_page × 64`).
- **Retention:** `retention_days` (365) and `max_records` (100 000) are link params; once a day (and at start) the oldest pages whose every record is closed go while they are older than the retention or the store holds more than the maximum; a page with an open record stays, as DSA never deletes an open alarm. `purge {before}` (config) removes closed records before an instant.
- A write the store refuses fails the action with `resource_exhausted` and leaves the state as before; for a record made from a sample it is logged at `error` and the record is dropped (counted in `stats/dropped`): nothing is half-saved.

### Sinks: the records go out through the history sync links (goal 4)
- `sinks/<name>` on the link, added with `add_sink {name, link, classes?, from: start | now}` (config): the link id that reads it (it signs as `link:<id>` with its requester key), the classes it takes (empty = all), and where its cursor starts. Its node's value is `confirmed_seq`; attributes `link`, `classes`, `lag_entries`, `rows_sent`, `dropped_unsent`, `last_request`. Actions `next {after?, max?}` (read; refused for any subject but `link:<its link>`: a person who ran it would confirm rows the database never got), `edit`, `reset {from}`, `remove` (config).
- `next` answers exactly as `sys/history/sinks/<name>` does: `{rows: [{seq, key, t, v, q}], next}`, `after` confirms every entry up to it, at most `max` (≤ 5 000) rows and 1 MiB. A row is a **record as the sync links already write it**: `key` = the record's source point, `t` = the record's `created`, `v` = the record as JSON text (`wyrm-alarm/1`: `{id, class, watch, source, type, message, value, created, normal, ack, ack_by, escalation, notes}`), `q` = `good`. The SQL and InfluxDB targets refuse a map value (ADR 0026: a row is one scalar), so the text form is the one every target takes; `(key, t)` is unique for a record, so a change rewrites the same row in the database, and the central database ends with the record's last state, as DSA's alarm database does. A target made for alarms (columns per field) is a later `Target` of `wyrm-history-sync`; nothing here changes for it.
- `wyrm-history-sync` takes a `sink` param of either shape, `wy/<site>/sys/history/sinks/<name>` or `wy/<site>/downstream/<link>/sinks/<name>`; nothing else in it changes. A package link reaches the sink under an operator's grant (`sys/links/<id>/~act/grant`, `read` on the sink's key, ADR 0013); a sink's `link` must be a link id, and the admin's audit of the `next` call names it.

### Rights (ADR 0022 ruling 6, ADR 0025 item 4, ADR 0029)
- `add_class`, a class's `edit`/`remove`, `raise`, `acknowledge`, `normal`, `add_note`, `ack_all`: `write`. `get_alarms`, `get_alarm`, `get_notes`, a class's `export`: `read`. `add_watch`, a watch's `edit`/`enable`/`disable`/`remove`, `import`, `add_sink` and the sink actions, `purge`: `config` (a watch subscribes a point; a sink confirms what left the site).
- **A watch keeps its author's rights:** `add_watch` and `import` refuse a caller whose token carries no `auth` (DQL's rule), refuse a source the author may not `read`, and keep the rights with the watch; a subtree watch drops the keys its author may not read. A watch keeps running after its author loses rights (as flows, schedules and queries).
- **A reader sees their own records:** `get_alarms`, `get_alarm`, `get_notes`, `acknowledge`, `normal`, `add_note` and `ack_all` check the caller's `auth` for `read` on the record's source, and refuse a caller without `auth` (their rights are unknown). `raise` needs none beyond `write` on the link (a dataflow's token carries no `auth`); its `source` must be a key of this site's tree. A class's table value `<class>/alarms` and the counters are for whoever may read those nodes (as a published DQL table): an engineer who gives a role `read` on the alarm link gives it the site's alarms.
- The embedded link reads `wy/<site>/downstream`, `dataflows` and `storage` (ADR 0025 D4: not other sites in this version); it writes nothing, so links need not trust its key. Packages carry no grants: an operator grants `read` on each root.

### Tree and actions
```
<link>/
  add_class {id, display?, escalation1_s?, escalation2_s?}  (write) -> {id}
  raise {class, source, type?, message?}                   (write) -> {id}   # a record no watch owns; `normal` ends it
  acknowledge {id, note?}  normal {id}  add_note {id, note}  ack_all {class?}   (write)
  get_alarm {id} -> map;  get_notes {id} -> rows;                              (read)
  get_alarms {timerange?, class?, source?, state?, type?, limit?} -> rows     (read; newest first)
  import {json, overwrite?}  purge {before}  add_sink {name, link, classes?, from?}   (config)
  stats/   open, active, unacked, records, watches, raised, dropped          (values)
  sinks/<s>   value confirmed_seq; attrs link, classes, lag_entries, rows_sent, dropped_unsent,
              last_request; next {after?, max?} (read, the sink's link only); edit, reset, remove (config)
  <class>/   folder; attrs display, escalation1_s, escalation2_s, created_by;
             add_watch (config); edit, remove, ack_all (write); export (read)
    open, active, unacked           counts (values)
    alarms                          the open records, newest first, at most 200 rows, published when
                                    they changed and at most every 500 ms
    watches/<w>   value: the state (normal | alarm | to_alarm | to_normal | disabled | error),
                  for a subtree watch `alarm` while any key is; attrs source, algorithm, type,
                  message, params, keys, in_alarm, last_change, last_record, error, created_by;
                  edit, enable, disable, remove (config)
```
A record's `state` in answers: `active` (not normal, not acknowledged), `acked` (acknowledged, still active), `normal` (normal, not acknowledged), `closed`. `get_alarms` `state` filters `open | active | unacked | closed | all` (default `open`); `timerange` is `<from>/<to>` in RFC 3339 on `created` (default: the open records, any time).

### The link
- **One timer** (as the scheduler): a min-heap of wakes — a watch's inhibit end, a staleness deadline per key, a record's escalations, the table publication, the daily purge — behind one host timer, at most 30 s ahead (the clock watchdog). A wall-clock step moves every wake by the step: inhibit and staleness are durations, not instants.
- **Batched work:** `start` declares the root, reads the open records, then loads the classes and, after each, its watches (a class may hold 500) in batches within the event budget, the rest in `0` ms timer events; a storm of samples is one record per sample event (two or three store writes each: the page, `open`, the journal page), so the cost per alarm is bounded and no event grows with the number of alarms. Through an action an enum is given by its index (the SDK's rule for `enum` params, as the scheduler's `confirm`); in an import, by its name.
- **Restart:** the classes and watches come from the store, the open records from `open`; a watched point's state starts as "record open" when an open active record names it, so its first normal sample closes it and its first alarm sample makes no second record; a staleness watch counts from the start. Manual records (`raise`) wait for `normal`.
- **Run modes:** embedded in `wyrmd` at `wy/<site>/downstream/alarm` (`alarm: { enabled: true, store_mb: 64 }`; the id reserved like `scheduler` and `dql`; its store key and requester key made by the admin, R22 on failure); process package `alarm-process` (`wyrmd link alarm`); WASM package `alarm` on world `wyrm:app@0.3.0`, store 16 MiB.

## Consequences
- The id `alarm` is reserved like `storage`, `scheduler` and `dql`; `wyrmd.json5` gains `alarm`.
- `wyrm-history-sync` accepts a link's sink as a source; the five database links take alarm records with no change of their own, as JSON text rows keyed by the source point and the creation time.
- Spec 02 does not change (existing editors and value types).
- A link grant at `read` lets the router pass `~act/*` queries under its path (never `~set`); the responder accepts only actions of level `read` with that grant's key. Found on the demo (2026-11-05, Docker run with PostgreSQL): a `postgres-process` link with `read` on `alarm/sinks/<name>` could not reach `next` through the router ACL, while a WASM package (in the broker's process, no ACL) could. Decided under ADR 0029 and written into `docs/links.md` § 10.
- Open items: an alarm target with one column per field (a `Target` of `wyrm-history-sync` for the SQL links); CEL conditions (DQL's bounded CEL); alarms over other sites' points (ADR 0025 D4 grants); a probe run on the demo with a real database container.
