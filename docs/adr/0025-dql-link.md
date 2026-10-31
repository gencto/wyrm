# ADR 0025 — DQL link: standing queries over the tree, as a portable link

**Status:** accepted · 2026-10-30, built (owner request: bring DSA `dslink-dart-dql` into WYRM so that it runs in every mode and works as the scheduler does — a portable `App`, embedded in every `wyrmd`, also a WASM and a process package). Owner decisions D1 … D6 of 2026-10-30 are listed at the end. Built: `crates/wyrm-dql`, `links/dql`, `wyr query`, the Host API amendment; user guide `docs/dql.md`; plan `docs/superpowers/plans/2026-10-30-dql-link.md`. Where the build differs from the text below, the rulings at the end (B1 …) say why.

## Context
DSA DQL ("distributed query language", `IOT-DSA/dslink-dart-dql` 0.6.2, analysed 2026-10-30) is a responder and requester link with one action, `/query {query}`, whose result is a streaming table. A query is a pipeline of commands separated by `|`:

```
list /downstream/System/* | filter $type="number" @unit!="%" | subscribe :name value | expression double="row.value * 2"
list /downstream/System | filter :metric | subscribe | invoke /downstream/MongoDB/local/SystemValues/publish(Path=%path, Value=%value)
```

Each command takes the stream of row updates (`{values, remove}`, row id = `path`) and gives another: `list`/`lista` (reactive recursive list; `*` any depth, `?` one segment; `, ` for more roots; directive `brokers`), `path` (one node), `sublist` (a list relative to each row), `filter`/`where` (tests on `$config`, `@attribute`, `:name`, columns; `= != < <= > >= ~ like contains anyContains in`, `and or xor not`, function calls; a test on a column subscribes it by itself), `subscribe`/`child` (value, `value.timestamp`, a child's value, `$config`, `@attr`, `:name`, `:displayName`, `:children`/`:configs`/`:attributes`, `as` column names), `expression` (a column from a script over `row`), `rename`, `drop`, `option` (`qos`, `traverseBrokers`, `listActions`, `invokeAllowNull`, `brokersIncludeQuarantine`) and `invoke` (call an action for each row with params from columns, `%col`, again when they change). Identical query texts share one running query (`QueryManager`); the link shows counts (`uniqueQueryCount`, `totalQueryCount`, `virtualListCount`, `virtualSubscribeCount`, `actionInvokeCount`) and `getRunningQueries`.

Kept: the pipeline language and its command names, row id = node path, columns in first-seen order, shared execution of identical texts, the counters, sinks that act on rows (`invoke`). Not kept, because they are its defects (read in the source):
- a query lives only while a requester holds its stream; nothing survives a restart, and a site without a client runs no query;
- `/query` is `$invokable: read`, and `invoke` runs with the link's own rights: whoever may read the link makes it call any action the link can reach (privilege escalation);
- no bounds: `list *` lists the whole network, one `list` per visited node, one subscription per row and column, unbounded rows, columns and invokes; one query can stall the broker;
- `expression` is a 5 600-line embedded JavaScript-like interpreter without a step or time bound;
- the `>=` test is an assignment (`result = v = against`), so it is always true for a non-null value; `sublist` removes rows with the parent's path instead of the child's, so rows of a removed parent stay;
- a removed row re-sends every row after it (`replace <id>-<len>`), O(n) per removal;
- an error in any stage closes the whole query with a stack trace as its message;
- `invoke` fires on every change with no rate limit and no bound on calls in flight.

WYRM already has what made DQL expensive in DSA: one key space with patterns (`wy/<site>/downstream/plc/**`), `resolve` (`view=keys&match=`) and pattern subscriptions for fan-in (spec 01). A query can be one subscription per root, not one per row.

## Goals
1. A query is configuration: stored, validated, running on the broker offline for months, back by itself after a restart (as a schedule, ADR 0022).
2. One language core for every way DQL runs: the link (embedded, process, WASM) and the CLI.
3. Results are ordinary nodes: anyone with `read` subscribes to a query's table; a dataflow, the explorer, the MCP server and an upstream site use it with no new protocol.
4. Bounded cost: per query and per link limits on rows, lists, subscriptions and sink calls; zero messages at idle when nothing changes.
5. A query cannot do more than its author may do; reading results never gives more rights than defining the query.
6. DSA queries import with a converter (`/downstream/X/*` → `wy/<site>/downstream/X/**`).

## Non-goals
- SQL, joins between queries, aggregation over time (history has `Get History` with rollups, ADR 0014; dataflows have windows).
- Streaming action replies (ADR 0023 non-goal); the results are a node, not a stream on `~act`.
- Queries that write `sys/**` or another site (owner decision 8, as flow sinks and scheduler targets).

## Anti-goals (a failure even if it works)
- One query, however wide, stalls the router, another link or the other queries.
- A user who may only read a part of the tree reads more through DQL.
- An `invoke` repeated after a restart that the author did not ask for.
- Load at idle that grows with the number of rows.

## Decision

### Language core (crate `wyrm-dql`: no I/O, no async, no clock; builds for `wasm32-unknown-unknown`)
- **Parser** (hand-written, no parser generator): text → `Plan` (stages, the columns each one adds or drops, sink targets, the roots), or an error with the stage index, the column and what was expected. At most 16 stages and 4 KiB of text.
- **Engine:** a pure state machine. Input: list changes of listed nodes, value samples, sink replies, `tick(now)`. Output: row changes (`upsert(path, columns)`, `remove(path)`) and the effects it wants (`list`, `unlist`, `subscribe`, `unsubscribe`, `invoke`, `set`). The host (link or CLI) performs the effects and feeds the results back. Every step is bounded; the same inputs give the same outputs (fixture tests, as `wyrm-schedule`).
- **Standards before our own code (D1):** the pipeline syntax is DSA DQL's (its users know it); paths are Zenoh key expressions (`*`, `**`, the transport's own standard); every expression and predicate is **CEL** (Common Expression Language, the Google specification used by Kubernetes, Envoy and Firebase rules), evaluated by the crate `cel-interpreter` (0.10, features `regex`, `chrono`; checked 2026-10-30 to build for `wasm32-unknown-unknown`); regular expressions are CEL `matches()` (RE2 syntax, crate `regex`). Our own code is only the pipeline parser and the row engine. CEL is not Turing-complete (no loops, no recursion; macros like `all`/`exists` are bounded by their list), so its cost is bounded by the expression and the row; the link adds a bound on expression text (1 KiB) and on list sizes in a row. Amended 2026-10-31 (local review; a nest of 5 `map`s over a 30-item literal took 4.8 s per row, and cel-rust cannot stop an evaluation): the bound is static, checked at compile: no macro inside another macro's arguments (a chain is linear), list literals ≤ 64 items, a bound value of more than 1 000 items is `null`.
- **Keys are full keys** (`wy/<site>/…`, "full site names everywhere"); the core does not know its own site. Wildcards follow Zenoh, not DSA: `*` is one segment, `**` any depth. A DSA text goes through `convert_dsa {text, site}` (`?` → `*`, a trailing `*` → `**`, `/downstream/…` → `wy/<site>/downstream/…`).

### The language (WYRM dialect; DSA names kept where they map)
| Command | WYRM meaning |
|---|---|
| `list <pattern>[, <pattern>…]` | Rows for nodes under the patterns, reactive (added, changed, removed, link gone). Folders and values; actions are not nodes in WYRM (`lista` and `listActions` are dropped, see `:actions`). |
| `list sites` | Rows for this site and the sites it sees (`upstream/*`, `downstream/*` brokers, `attr.root`); DSA `brokers`. A pattern under another site's key (`wy/plant/downstream/**`) lists that site through the peer link within the ACL (ADR 0018) — in the first version (D4); DSA `traverseBrokers` is not needed, the key says where. |
| `path <key>` | One row for one node. |
| `sublist <pattern>` | A list relative to each row (`./*`, `./**`); its rows replace the parent's. |
| `where <CEL>` | A CEL predicate over the row: `type == "number" && attr.unit != "%"`, `name.matches("^ahu[0-9]+$")`, `value > 20.0`. Variables: the columns, and `meta` fields as `type`, `unit`, `writable`, `is` (profile), `display`, `name`, `attr` (map), `actions` (list of names), `path`. |
| `filter <DSA tests>` | DSA syntax kept for imported queries (`$type="number" @unit!="%" :name`); the parser turns it into the same CEL (`$x` → `x`, `@a` → `attr.a`, a bare key → `has(...)`, `like` → `matches()`), so there is one evaluator. A test on a column that no earlier stage made subscribes that column first (as DSA). |
| `subscribe [<key> [as <col>]]…` / `child` | `value` (default), `value.timestamp` → the sample's `t`, `value.quality` (new), a child's value (`./setpoint`), `$…`, `@…`, `:name`, `:display`, `:children`. |
| `expression <col>="<CEL>"…` | A column from a CEL expression over the row (`value * 2.0`, `string(value) + " " + unit`); DSA's JavaScript-like `row.value` is accepted as `row.value` (the row is also bound as `row`). |
| `rename <a> as <b>`, `drop <cols>`, `option <k>=<v>` | As DSA. Options: `invoke_allow_null`, `throttle_ms`, `max_rows`, `timeout_s` (see "Wide and deep trees"). `qos` is accepted and ignored (spec 03 QoS belongs to the point, `cfg.qos`). |
| `invoke <node>/~act/<action>(<p>=%<col>, <p>=<literal>…)` | For each row, call the action when the referenced columns change. `<node>` is a full key or relative to the row (`./`, `../`). |
| `set <node> = <expr>` | New: write a value to a point for each row when it changes (`~set`; a write sink is more common in WYRM than an action). |

- **Expressions:** CEL as specified, with its standard functions and macros; `wyrm_core::Value` maps to CEL values one to one (map, list, int, uint, double, string, bytes, bool, null; the sample time as a CEL `timestamp`). No functions of our own in the first version. An expression that fails on a row (a type error, a missing key) gives `null` in that column and a count in the query's `errors`, not the end of the query; a text that does not compile is refused at `add_query`/`run` with the stage and CEL's message.
- **Rows:** id = node key; columns in first-seen order; values are `wyrm_core::Value`.

### Host API: two additive changes (an amendment to ADR 0023)
DQL needs what the scheduler did not: to see the tree and to subscribe a subtree with one subscription.
- `Host::list(key, full) -> Result<SubId, AppError>` (B2) — reactive one-level list (as `wyrm-client` `list`): `App::on_list(sub, key, change)` with `change = Refreshed(children) | Added(child) | Changed(child) | Removed(name) | Disconnected`, a child = `(name, NodeMeta)`. Needs `read` on the key; ended by `unsubscribe`; counts toward a new bound `max_lists` (2 000 per instance). A full queue coalesces a list's changes into a `Refreshed`.
- `Host::subscribe(key)` accepts one final `/**` segment: one subscription for a subtree (fan-in); `read` on the prefix; each sample comes with its node key (`on_value` already has it). No other wildcard.
- WIT: `wyrm:app@0.1.0` stays frozen (ADR 0022 ruling 2), so components built on it keep loading. A new `wyrm:app@0.2.0` world is a superset: import `list`, export `on-list`; the WASM host tells the two worlds apart by their exports (as it tells `point` from `driver`). The scheduler moves to 0.2.0 only when it is rebuilt.

### The link (`links/dql`: an `App`, as `links/scheduler`)
```
<link>/                            attrs: queries, rows, lists, subscriptions, sink_calls (DSA counters)
  add_query {id, display?, text, enabled?, publish_ms?}   (write; sinks need config) -> {id}
  explain {text}                   (read)   -> {stages, columns, roots, sinks, errors}
  run {text, id?, ttl_s?}          (write; sinks need config) -> {id, table}   # ad-hoc, shared by identical text
  import {json, id?, overwrite?}   (config)              # own export or a DSA text
  convert_dsa {text, site}         (read)   -> {text}
  <query>/                         folder; attrs display, text, status (collecting | ready | error | disabled),
                                   error, rows, columns, errors, created_by, expires (ad-hoc only),
                                   progress: lists, lists_pending, depth, sites, collect_ms, last_publish
    table                          the table: an array of row maps, columns order in attr `columns`
    enabled                        writable bool; saved
    get_table {from?, limit?}      (read)  -> rows
    edit {display?, text?, publish_ms?}  (as add_query); export (read) -> {json}; remove (write)
```
- **Results as nodes:** `table` is published when it changed, at most every `publish_ms` (default 500 ms, 100 … 60 000) — coalesced, never per sample; with no change there is no message. Readers subscribe to it (explorer, flows, MCP, upstream sites); `get_table` pages it (≤ 5 000 rows per reply). No per-row nodes: rows come and go faster than a tree should change, and the node budget would bound rows.
- **Ad-hoc queries** (DSA `/query`): `run` returns the id and the `table` key of a temporary query with `ttl_s` (default 300 s, ≤ 3 600); `get_table` or `run` again with the same text renews it; identical text shares one (DSA `QueryManager`). With `id` the caller names it, so a dataflow can subscribe a fixed key (`…/dql/<id>/table`) in its definition. It is not stored: it ends with the instance.
- **Who asks (D2):** engineers (explorer, `wyr`, the agent through actions) and, later, dataflows: the broker collects data through the DQL link from a flow — a flow `invoke` sink calls `run {id, text}` (or the engineer defines a standing query) and a flow `subscribe` source reads `<id>/table`, waiting for `status: ready` when it needs a complete table. A one-shot `query {text, timeout_ms} -> rows` that answers when the table is complete needs deferred replies in the portable API (ADR 0023 non-goal today); it is left for the dataflow work.
- **Persistence:** host store `index` (the ids) and `q/<id>` (definition: `{id, display, text, enabled, publish_ms, created_by}`), written in the event that accepts the edit. Results are not stored; after a restart the query is evaluated again from the live tree (principle 3: what is not re-declared does not exist).
- **One subscription per root:** the engine subscribes `<topmost fixed prefix>/**` once for all value columns of a root and drops samples of keys that are not rows; `list` runs only on the levels the pattern can reach.
- **Bounds** (constants of `links/dql`, one place each, refused with `resource_exhausted` before the host would fail the event): 200 queries; rows per query `max_rows` (default 1 000, ≤ 5 000; over it the query shows `error: max_rows` and keeps the first rows); lists 1 000 per query (B3) and 2 000 per link; subscriptions 1 000 per link; sink calls 50 in flight per link (the rest wait in a FIFO, as scheduler writes) and at most one in flight per row; at most 800 commands and 500 ms of batched work per event, the rest in `0` ms timer events (ADR 0022 ruling 5); nodes 5 per query (1 000 queries' worth below the 10 000-node host bound).
- **Sinks (D3, D5):** `set` and `invoke` fire when the values they use change, and not for a row whose values are null (unless `invoke_allow_null`). After a start (a restart, an edit, `enabled` on, a row that appears) the first values seen are the baseline: neither sink fires until the state changes from it (D5: no write and no call repeated after a restart). There is no option to fire on start. `throttle_ms` (default 0) holds a row's next call. A failed call is counted in `errors` and logged at `info` (ids only, never values); it is not retried (an action is not idempotent).
- **Rights (D2; as ADR 0022 ruling 6):** a `ptok` carries one grant narrowed to the request key, so the link cannot see the caller's rights on the keys a query lists; it does see the caller's level on its own action key (`SigningTokens::scoped` keeps the level). So:
  - a query without sinks (`add_query`, `run`, `edit`, `remove`) is `write`: engineers, the agent (capped at `write`) and dataflows (the flow key is trusted at `write`; a deploy proof per target, ADR 0008) may define and run them; whoever has `write` on the DQL link may read what the link reads — the guide says so, and roles that must not see the whole site get no `write` on it;
  - a query with a sink (`set`, `invoke`) needs the caller's **effective** level `config` on the action key: the app checks `who` and refuses with `permission_denied` otherwise. The SDK must give the app the effective level (the claim capped by a `LimitedKey`'s limit), so a flow or agent key never passes as `config`; the builder checks `who_of` and fixes it if it passes the raw claim. Flows therefore cannot create sink queries (they have their own `set`/`invoke` sinks);
  - `import` is `config` (it may carry sinks); reading results (`table`, `get_table`, `explain`) is `read`.
  A query keeps running after its author loses rights (as flows and schedules); `created_by` = `who.subject`. The full-grants claim in `ptok` (the scheduler's open item) would allow checks against the author's own rights on every key; not in this version.
- **Grants of the link:** embedded — `read` on `wy/<site>/{downstream,dataflows,storage,upstream}` and `write` on `wy/<site>/downstream` (sinks), signed with its own admin-made key (subject `link:dql`), trusted by links as a `LimitedKey` at `write`, and not by itself (no query writing its own nodes in a loop, ADR 0022 ruling R21). Packages carry no `requester` grants; an operator grants each root (`sys/links/<id>/~act/grant`, ADR 0013). A query on keys outside the grants shows `status: error` with the host's `permission_denied`.

### Wide and deep trees, other sites (D4)
Collecting a table can take time: one `list` round trip per level the pattern reaches, a peer hop per site (QUIC, ADR 0007), links that answer slowly. The link does not hide it, and the numbers tell us where the time goes once trees are big and deep:
- `status: collecting` until every list the query started gave its first `Refreshed` (or failed), then `ready`; a change later keeps `ready`. `timeout_s` (default 30 s, ≤ 600) marks a query `ready` with `error: incomplete (<n> lists pending)` when lists are still pending, and keeps waiting for them in the background.
- Progress attributes on the query: `lists` (running), `lists_pending`, `depth` (deepest level reached), `sites` (sites touched), `collect_ms` (start to `ready`), `last_publish`. Counters on the link root: `rows`, `lists`, `subscriptions`, `sink_calls`, `slowest_collect_ms`.
- The guide (`docs/dql.md`) states the cost: a pattern with `**` near the top of a big site, or across sites, lists every level under it; prefer the narrowest fixed prefix (`wy/plant/downstream/plc1/**`, not `wy/plant/**`).
- Lists of another site go through the router to that site's links like any request from above (ADR 0018 read rules); the first-query timeout across peers in the backlog applies to them.

### Run modes (one core, four hosts)
- **Embedded in `wyrmd`** — the default, as the scheduler: one instance at `wy/<site>/downstream/dql`, `dql: { enabled: true, store_mb: 16 }` in `wyrmd.json5`; the id `dql` reserved (`validate_new_link_id`, `Daemon::open` refuses a stored link with it, `peers.downstream` cannot name a site `dql`); in the broker's overlays; a failure to make its keys logs and the broker runs without it (ADR 0022 ruling R22).
- **Process package** `dql-process` — `process::main::<Portable<Dql>>()`; `wyrmd link dql` runs the same app as a process link.
- **WASM package** `dql` — the same `App`, `--features wasm`, world `wyrm:app@0.2.0`, `capabilities = { store_mb = 4 }`.
- **CLI** `wyr query "<text>"` — the same engine over `wyrm-client` with the user's own token: the ad-hoc, streaming DSA experience in a terminal (rows printed as they change, `--json`), rights checked by the router for the user, nothing stored. Later the same core can back an MCP `query` tool and a flow source node (DSA "DQL as an embedded library").

### Tests and benchmarks
- Parser fixtures: DSA's `statement_grammar.yaml` cases converted, every example of the DSA README converted by `convert_dsa` and parsed; errors name stage and column.
- Engine fixtures (no host): list add/change/remove, link disconnected, sublist removal (the DSA bug), `>=` (the DSA bug), filter that stops matching (row removed), auto-subscribe of filter columns, expression errors as null, sinks on change only and never on start (D5: a restart with the same values calls nothing), throttle, CEL errors as null, DSA `filter` → CEL translation.
- The app on all three hosts with one scenario (as `scheduler_three_modes`): a query over `mock`, its table, a restart (definition back, table rebuilt, no repeated `invoke`), a sink outside the grants.
- Probe scenario `links/probe/scenarios/dql.json`; user guide `docs/dql.md`.
- Benchmarks (targets on the reference board): 10 000 mock points, `list wy/<s>/downstream/mock/** | where type == "number" | subscribe` — table complete < 2 s, one subscription; at 50k samples/s the query adds < 10 % of one core; table publication p99 < `publish_ms` + 50 ms; idle: 0 messages. Deep and remote trees (D4), measured and recorded, not yet targets: `collect_ms` for depth 2, 4, 8 and fan-out 10, 100 under mock, on this site and across the demo chain (`central` querying `plant` through `edge`).

## Consequences
- ADR 0023 gains `Host::list`, `App::on_list`, the `/**` subscribe pattern and the `wyrm:app@0.2.0` world; `wyrm-link-api`, `wyrm-link-portable`, `wyrm-link-guest`, `wyrm-wasm-host`, `links/wasm` change; the 0.1.0 world and its components are untouched.
- New crates `crates/wyrm-dql`, `links/dql`; `wyr query`; the id `dql` is reserved like `storage` and `scheduler`.
- Spec 02 does not change (existing value types and editors; the table is an array of maps).
- `examples/packages/build.sh` packs `dql` and `dql-process`.

## Rulings of the build (B1 …)
- **B1 — CEL crate:** `cel` 0.15 (cel-rust, the maintained successor of `cel-interpreter`), features `regex` only. `cel-interpreter` 0.10 panics on some invalid texts (`1 +`: an antlr `unreachable!`), which would restart the instance; 0.15 answers them as errors. No `chrono` (its tz database is large in WASM): no CEL `timestamp`/`duration`; sample times are microseconds (`value.timestamp`).
- **B2 — full meta on demand:** `view=list` summaries carry no `attr` and no `actions`, which DSA filters use (`@mytag`). `Host::list(key, full)`: with `full` the host fetches each child's whole `~meta` (one request more per child). A query asks for it only when a stage reads `attr`, `actions` or `meta` (or `list sites`).
- **B3 — lists per query:** 1 000 (not 500): a site of 900 devices under one pattern fits; over it the query is `ready` with `error: max_lists …`.
- **B4 — other sites in the host:** `BufferHost` let a portable link reach only its own site. `subscribe` and `list` now reach another site's keys under an explicit grant; `set` and `invoke` stay on the link's own site (owner decision 8). The embedded link gets `read` on `downstream`, `dataflows`, `storage` of every site `Peers::reachable` names, per router build.
- **B5 — effective level in `Who`:** the portable runtime gave the app the raw `ptok` grants; it now caps each at the request's effective level (`Caller.perm`, a `LimitedKey`'s limit), so a flow or agent token never shows `config`.
- **B6 — counters:** the link root belongs to the host (ADR 0023), so the DQL counters are values under `stats/` (`stats` is a reserved query id).
- **B7 — node ownership:** the embedded DQL link does not trust its own key (as the scheduler, R21), so no query writes the DQL link's own nodes.
- **B8 — a fixed `sublist`:** as `list`, a pattern without a wildcard lists that node's children (`sublist ./temp` = the children of `temp`).
- **B9 — not yet:** a probe scenario on the demo, the three-mode e2e of the DQL link with its WASM and process packages, and benchmarks on the reference board. Tested: the engine and the link on `SimHost`, both world versions in `wyrm-wasm-host`, and e2e `dql_embedded_queries_the_tree` (the embedded link through a real router: a live table, its publication, a `set` sink only after a change); `scheduler_three_modes` and `one_app_three_modes` pass with guests built on 0.2.0.
- **B10 — the grant a request carries:** a `ptok` carries the first configured grant that covers its key, so a `read` grant on `downstream` listed before the `write` one sent sink writes at `read` (found by the e2e). The portable runtime now orders the link's grants by level, highest first.

## Owner decisions (2026-10-30)
- **D1 — standards, fewer own solutions:** CEL for expressions and predicates (`cel-interpreter`), Zenoh key expressions for paths, RE2-style regex in CEL; DSA DQL pipeline syntax kept; no own expression language, no `rhai` here (not a standard).
- **D2 — who asks:** engineers now and dataflows later (the broker collects data through the link): queries without sinks at `write`, sink queries at effective `config`.
- **D3 — `set` sink:** added.
- **D4 — other sites:** in the first version; collection time is shown (`collecting`/`ready`, progress, `collect_ms`) and measured on deep and remote trees.
- **D5 — after a restart:** wait for a change of state; no sink fires on start.
- **D6 — WIT world (confirmed: a new `wyrm:app@0.2.0`):** a WASM link is built against a contract (WIT world) that lists what the broker gives it and what it must export. DQL needs one new broker function (`list`) and one new export (`on-list`). The scheduler's WASM package, already installed on sites, is built on `wyrm:app@0.1.0`, which lacks `on-list`. Changing 0.1.0 in place would make the broker expect `on-list` from every component and refuse the installed scheduler until it is rebuilt and reinstalled everywhere. A new `wyrm:app@0.2.0` beside 0.1.0 (proposed) lets old components keep running untouched and new ones (DQL, a rebuilt scheduler) use the new functions; the broker supports both.
