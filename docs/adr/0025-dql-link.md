# ADR 0025 — DQL link: standing queries over the tree, as a portable link

**Status:** proposed · 2026-10-30 (owner request: bring DSA `dslink-dart-dql` into WYRM so that it runs in every mode and works as the scheduler does — a portable `App`, embedded in every `wyrmd`, also a WASM and a process package). Needs the owner decisions at the end before a plan is written.

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
- **Keys are full keys** (`wy/<site>/…`, "full site names everywhere"); the core does not know its own site. Wildcards follow Zenoh, not DSA: `*` is one segment, `**` any depth. A DSA text goes through `convert_dsa {text, site}` (`?` → `*`, a trailing `*` → `**`, `/downstream/…` → `wy/<site>/downstream/…`).

### The language (WYRM dialect; DSA names kept where they map)
| Command | WYRM meaning |
|---|---|
| `list <pattern>[, <pattern>…]` | Rows for nodes under the patterns, reactive (added, changed, removed, link gone). Folders and values; actions are not nodes in WYRM (`lista` and `listActions` are dropped, see `:actions`). |
| `list sites` | Rows for this site and the sites it sees (`upstream/*`, `downstream/*` brokers, `attr.root`); DSA `brokers`. Listing *under* another site needs `option sites=true` (DSA `traverseBrokers`). |
| `path <key>` | One row for one node. |
| `sublist <pattern>` | A list relative to each row (`./*`, `./**`); its rows replace the parent's. |
| `filter <tests>` / `where` | Tests on meta and columns: `$type`, `$unit`, `$writable`, `$is` (profile), `$display`, `@<attr>`, `:name`, `:display`, `:actions` (action names), and any column. Ops `= == != < <= > >= like contains in ~` (regex: `regex-lite`), `and or xor not`, parentheses, the DSA functions. A test on a column that no earlier stage made subscribes that column first (as DSA). |
| `subscribe [<key> [as <col>]]…` / `child` | `value` (default), `value.timestamp` → the sample's `t`, `value.quality` (new), a child's value (`./setpoint`), `$…`, `@…`, `:name`, `:display`, `:children`. |
| `expression <col>="<expr>"…` | A small expression language (below), not JavaScript. |
| `rename <a> as <b>`, `drop <cols>`, `option <k>=<v>` | As DSA. Options: `sites`, `invoke_on_start`, `invoke_allow_null`, `throttle_ms`, `max_rows`. `qos` is accepted and ignored (spec 03 QoS belongs to the point, `cfg.qos`). |
| `invoke <node>/~act/<action>(<p>=%<col>, <p>=<literal>…)` | For each row, call the action when the referenced columns change. `<node>` is a full key or relative to the row (`./`, `../`). |
| `set <node> = <expr>` | New: write a value to a point for each row when it changes (`~set`; a write sink is more common in WYRM than an action). |

- **Expressions:** numbers, text, booleans, null; columns by name or `row.<name>`; `+ - * / %`, comparisons, `and or not`, `if(c, a, b)`; functions `min max abs round floor ceil pow sqrt log sin cos tan concat join index len lower upper substr now_us`. No loops, no assignment, at most 256 nodes per expression and 10 000 steps per row; a failure gives `null` in that column and a count in the query's `errors`, not the end of the query.
- **Rows:** id = node key; columns in first-seen order; values are `wyrm_core::Value`.

### Host API: two additive changes (an amendment to ADR 0023)
DQL needs what the scheduler did not: to see the tree and to subscribe a subtree with one subscription.
- `Host::list(key) -> Result<SubId, AppError>` — reactive one-level list (as `wyrm-client` `list`): `App::on_list(sub, key, change)` with `change = Refreshed(children) | Added(child) | Changed(child) | Removed(name) | Disconnected`, a child = `(name, NodeMeta)`. Needs `read` on the key; ended by `unsubscribe`; counts toward a new bound `max_lists` (2 000 per instance). A full queue coalesces a list's changes into a `Refreshed`.
- `Host::subscribe(key)` accepts one final `/**` segment: one subscription for a subtree (fan-in); `read` on the prefix; each sample comes with its node key (`on_value` already has it). No other wildcard.
- WIT: `wyrm:app@0.1.0` stays frozen (ADR 0022 ruling 2), so components built on it keep loading. A new `wyrm:app@0.2.0` world is a superset: import `list`, export `on-list`; the WASM host tells the two worlds apart by their exports (as it tells `point` from `driver`). The scheduler moves to 0.2.0 only when it is rebuilt.

### The link (`links/dql`: an `App`, as `links/scheduler`)
```
<link>/                            attrs: queries, rows, lists, subscriptions, sink_calls (DSA counters)
  add_query {id, display?, text, enabled?, publish_ms?}   (config) -> {id}
  explain {text}                   (read)   -> {stages, columns, roots, sinks, errors}
  run {text, ttl_s?}               (config) -> {id}     # an ad-hoc query, shared by identical text
  import {json, id?, overwrite?}   (config)              # own export or a DSA text
  convert_dsa {text, site}         (read)   -> {text}
  <query>/                         folder; attrs display, text, status (running | error | disabled),
                                   error, rows, columns, errors, created_by, expires (ad-hoc only)
    table                          the table: an array of row maps, columns order in attr `columns`
    enabled                        writable bool; saved
    get_table {from?, limit?}      (read)  -> rows
    edit {display?, text?, publish_ms?}  (config); export (read) -> {json}; remove (config)
```
- **Results as nodes:** `table` is published when it changed, at most every `publish_ms` (default 500 ms, 100 … 60 000) — coalesced, never per sample; with no change there is no message. Readers subscribe to it (explorer, flows, MCP, upstream sites); `get_table` pages it (≤ 5 000 rows per reply). No per-row nodes: rows come and go faster than a tree should change, and the node budget would bound rows.
- **Ad-hoc queries** (DSA `/query`): `run` returns the id of a temporary query with `ttl_s` (default 300 s, ≤ 3 600); `get_table` or `run` again with the same text renews it; identical text shares one (DSA `QueryManager`). It is not stored: it ends with the instance.
- **Persistence:** host store `index` (the ids) and `q/<id>` (definition: `{id, display, text, enabled, publish_ms, created_by}`), written in the event that accepts the edit. Results are not stored; after a restart the query is evaluated again from the live tree (principle 3: what is not re-declared does not exist).
- **One subscription per root:** the engine subscribes `<topmost fixed prefix>/**` once for all value columns of a root and drops samples of keys that are not rows; `list` runs only on the levels the pattern can reach.
- **Bounds** (constants of `links/dql`, one place each, refused with `resource_exhausted` before the host would fail the event): 200 queries; rows per query `max_rows` (default 1 000, ≤ 5 000; over it the query shows `error: max_rows` and keeps the first rows); lists 500 per query and 2 000 per link; subscriptions 1 000 per link; sink calls 50 in flight per link (the rest wait in a FIFO, as scheduler writes) and at most one in flight per row; at most 800 commands and 500 ms of batched work per event, the rest in `0` ms timer events (ADR 0022 ruling 5); nodes 5 per query (1 000 queries' worth below the 10 000-node host bound).
- **Sinks:** `set` and `invoke` fire when the values they use change, and not for a row whose values are null (unless `invoke_allow_null`). After a start (a restart, an edit, `enabled` on) `set` writes the current value (a state, idempotent) but `invoke` waits for the first change, unless `option invoke_on_start=true` (anti-goal: no repeated invoke after a restart). `throttle_ms` (default 0) holds a row's next call. A failed call is counted in `errors` and logged at `info` (ids only, never values); it is not retried (an action is not idempotent).
- **Rights (as ADR 0022 ruling 6):** a `ptok` carries one grant narrowed to the request key, so the link cannot see the caller's rights on the keys a query lists. Therefore defining a query (`add_query`, `edit`, `import`, `run`) is `config`; reading results (`table`, `get_table`, `explain`) is `read`. Whoever has `config` on the DQL link may read what the link reads and write where it writes; the gateway's `operator` (write) cannot define queries, `engineer` and `admin` can. A query keeps running after its author loses rights (as flows and schedules); `created_by` = `who.subject`. Left open for the owner: the full-grants claim in `ptok` (the scheduler's open item) would let `read` users run ad-hoc queries checked against their own rights.
- **Grants of the link:** embedded — `read` on `wy/<site>/{downstream,dataflows,storage,upstream}` and `write` on `wy/<site>/downstream` (sinks), signed with its own admin-made key (subject `link:dql`), trusted by links as a `LimitedKey` at `write`, and not by itself (no query writing its own nodes in a loop, ADR 0022 ruling R21). Packages carry no `requester` grants; an operator grants each root (`sys/links/<id>/~act/grant`, ADR 0013). A query on keys outside the grants shows `status: error` with the host's `permission_denied`.

### Run modes (one core, four hosts)
- **Embedded in `wyrmd`** — the default, as the scheduler: one instance at `wy/<site>/downstream/dql`, `dql: { enabled: true, store_mb: 16 }` in `wyrmd.json5`; the id `dql` reserved (`validate_new_link_id`, `Daemon::open` refuses a stored link with it, `peers.downstream` cannot name a site `dql`); in the broker's overlays; a failure to make its keys logs and the broker runs without it (ADR 0022 ruling R22).
- **Process package** `dql-process` — `process::main::<Portable<Dql>>()`; `wyrmd link dql` runs the same app as a process link.
- **WASM package** `dql` — the same `App`, `--features wasm`, world `wyrm:app@0.2.0`, `capabilities = { store_mb = 4 }`.
- **CLI** `wyr query "<text>"` — the same engine over `wyrm-client` with the user's own token: the ad-hoc, streaming DSA experience in a terminal (rows printed as they change, `--json`), rights checked by the router for the user, nothing stored. Later the same core can back an MCP `query` tool and a flow source node (DSA "DQL as an embedded library").

### Tests and benchmarks
- Parser fixtures: DSA's `statement_grammar.yaml` cases converted, every example of the DSA README converted by `convert_dsa` and parsed; errors name stage and column.
- Engine fixtures (no host): list add/change/remove, link disconnected, sublist removal (the DSA bug), `>=` (the DSA bug), filter that stops matching (row removed), auto-subscribe of filter columns, expression errors as null, sinks on change only, `invoke_on_start`, throttle.
- The app on all three hosts with one scenario (as `scheduler_three_modes`): a query over `mock`, its table, a restart (definition back, table rebuilt, no repeated `invoke`), a sink outside the grants.
- Probe scenario `links/probe/scenarios/dql.json`; user guide `docs/dql.md`.
- Benchmarks (targets on the reference board): 10 000 mock points, `list wy/<s>/downstream/mock/** | filter $type="number" | subscribe` — table complete < 2 s, one subscription; at 50k samples/s the query adds < 10 % of one core; table publication p99 < `publish_ms` + 50 ms; idle: 0 messages.

## Consequences
- ADR 0023 gains `Host::list`, `App::on_list`, the `/**` subscribe pattern and the `wyrm:app@0.2.0` world; `wyrm-link-api`, `wyrm-link-portable`, `wyrm-link-guest`, `wyrm-wasm-host`, `links/wasm` change; the 0.1.0 world and its components are untouched.
- New crates `crates/wyrm-dql`, `links/dql`; `wyr query`; the id `dql` is reserved like `storage` and `scheduler`.
- Spec 02 does not change (existing value types and editors; the table is an array of maps).
- `examples/packages/build.sh` packs `dql` and `dql-process`.

## Open owner decisions
1. **Expression language:** our small one in `wyrm-dql` (proposed: bounded, small in WASM) vs `rhai` as `wyrm-flow` uses (one language for flows and DQL, but larger, and its wasm32 build needs checking).
2. **Who may define queries:** `config` (proposed, safe today) vs `write` for read-only queries (needs the full-grants `ptok` claim, spec 04, in every SDK).
3. **`set` sink:** add it (proposed) or keep DSA's `invoke` only.
4. **Cross-site queries:** `option sites=true` reads under other sites within the ACL (ADR 0018) in the first version, or later.
5. **`invoke` after a restart:** wait for the first change (proposed) vs DSA's behaviour (invoke every row at once).
6. **WIT:** a new `wyrm:app@0.2.0` world (proposed) vs adding `list` to 0.1.0 (simpler, but breaks the "frozen" rule of ADR 0022 ruling 2).
