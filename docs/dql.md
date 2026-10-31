# DQL — queries over the tree

DQL ("distributed query language", after DSA's `dslink-dart-dql`) finds nodes, reads their
values and meta, computes columns and can write the result back to points. A query is a
pipeline:

```
list wy/plant/downstream/plc1/** | where type == "number" && attr.unit == "°C"
  | subscribe value :name | expression f="value * 1.8 + 32.0"
```

Its result is a **table**: one row per node (the row id is the node key), one column per
`subscribe`, `expression` or meta field. Design: ADR 0025.

## Where it runs

| Mode | What | Rights |
|---|---|---|
| Embedded (default) | `wy/<site>/downstream/dql` in every `wyrmd` | reads this site's `downstream`, `dataflows`, `storage`, `upstream` and the readable sections of downstream sites; sinks write only this site's `downstream` |
| WASM package `dql` | the same link, installed from a repository or zip | what an operator grants (`sys/links/<id>/~act/grant`): `read` on each root, `write` on each sink target |
| Process package `dql-process` | the same link as a process | as the WASM package |
| `wyr query "<text>"` | the same engine in the terminal, nothing stored | your own token |

`wyrmd.json5`: `dql: { enabled: true, store_mb: 16 }` (both optional). The id `dql` is reserved.

## The link's tree

```
dql/
  add_query {id, text, display?, enabled?, publish_ms?}    write; a query with set/invoke needs config
  run {text, id?, ttl_s?} -> {id, table}                   ad-hoc, not stored
  explain {text} -> {stages, columns, roots, sinks, errors}
  import {json, id?, overwrite?}                           config
  convert_dsa {text, site} -> {text}
  stats/queries, rows, lists, subscriptions, sink_calls
  <query>/                 attrs: text, status, error, rows, columns, errors, sink_calls,
                           lists, lists_pending, depth, sites, collect_ms, last_publish,
                           created_by, expires (ad-hoc)
    table                  the rows: an array of maps, in key order
    enabled                writable
    get_table {from?, limit?} -> {rows, total, columns, status}
    edit {display?, text?, publish_ms?}, export -> {json}, remove
```

- **Stored queries** (`add_query`, `import`) live in the link's store and come back after a
  restart; their table is rebuilt from the live tree (nothing of the old result is kept).
- **Ad-hoc queries** (`run`) end after `ttl_s` (300 s, at most 3 600) unless `get_table` or
  `run` with the same text renews them. The same text shares one query. With `id` a dataflow
  can subscribe a fixed key: `…/dql/<id>/table`.
- **The table** is published at most every `publish_ms` (500 ms; 100 … 60 000) and only when it
  changed: a quiet tree sends nothing.

## Collection takes time

Each level a pattern reaches is one `list` round trip; another site adds a peer hop. A query
shows:

- `status`: `collecting` until every list it opened answered once, then `ready`
  (`disabled`, `error` when its text no longer parses);
- `lists`, `lists_pending`, `depth` (deepest level reached), `sites`, `collect_ms` (start to
  `ready`);
- `error`: why the table may be incomplete — `max_rows`, `max_lists`, a refused list, or
  `incomplete: N lists pending after T s` (`option timeout_s`, default 30 s).

Prefer the narrowest fixed prefix: `wy/plant/downstream/plc1/**`, not `wy/plant/**`. A pattern
with `**` near the top of a big site lists every folder below it.

## Commands

| Command | Meaning |
|---|---|
| `list <pattern>[, <pattern>…]` | Rows for nodes under the patterns. Keys are full (`wy/<site>/<section>/…`); `*` is one segment, `**` any number. A pattern without a wildcard lists that node's children. Folders are listed, values are not (they have no children). |
| `list sites wy/<site>` | Broker nodes the site sees: `upstream/*` and `downstream/*` with `attr.root` (DSA `brokers`). |
| `path <key>` | One row: that node. |
| `sublist <pattern>` | Below each row: `./*`, `./**`, `./a/*`. Its rows replace the parent's; a parent that goes takes its rows with it. |
| `where <CEL>` | Keeps rows for which the predicate is `true`. |
| `filter <DSA tests>` | DSA's syntax, turned into CEL: `$type="number" @unit!="%" :name like 'Temp%' value >= 20`. Tests side by side all hold. |
| `subscribe [<key> [as <col>]]…` | Columns: `value` (default), `value.timestamp` (µs), `value.quality`, a child (`./setpoint`, `setpoint.timestamp`), `$type`, `$unit`, `$writable`, `$is`, `$display`, `@<attr>`, `:name`, `:display`, `:path`, `:actions`. |
| `expression <col>="<CEL>"…` | Computed columns. |
| `rename <a> as <b>` · `drop <cols>` | As DSA. |
| `option k=v …` | `throttle_ms`, `max_rows` (1 000; at most 5 000), `timeout_s` (30; at most 600), `invoke_allow_null`. DSA's `qos`, `traverseBrokers`, `listActions` are accepted and ignored. |
| `set <node> = <CEL or %col>` | Writes the value to a point (`~set`) for each row. `<node>` is a full key or relative to the row (`.`, `..`, `./x`). |
| `invoke <node>/~act/<action>(<p>=<CEL or %col>, …)` | Calls an action for each row; `invoke ack(…)` calls `ack` on the row itself. |

A name a `where`, `expression` or sink uses that no stage made is subscribed first: `value` is
the row's value, any other name a child's (as DSA's filter did).

## Expressions: CEL

Predicates and expressions are [CEL](https://github.com/google/cel-spec) (Common Expression
Language, the standard used by Kubernetes, Envoy and Firebase), evaluated by the `cel` crate.
Variables of a row:

- its columns, by name (`value`, `f`), and all of them as the map `row` (`row["value.timestamp"]`);
- its meta: `path`, `name`, `type`, `unit`, `writable`, `is`, `display`, `quality`, `attr` (map),
  `actions` (list of names), and all of it as `meta`.

Examples: `type == "number" && value > 20.0`, `name.matches("^ahu[0-9]+$")`,
`"unit" in attr && attr.unit == "%"`, `string(value) + " " + unit`, `[1, 2].exists(x, x > value)`.

An expression that fails on a row (a type error, a missing key) gives `null` in that column;
it counts in `errors` only when what it reads is there (`value + 1` before the first sample is
not an error). A `where` that fails drops the row.

Reading `attr`, `actions` or `meta` makes the query fetch each listed node's whole `~meta`
(one more request per node): use it on narrow patterns.

## Sinks: set and invoke

- A query with a sink needs `config` on the DQL link (the gateway's `engineer`, `admin`); `write`
  (`operator`, the agent, dataflows) may define queries without sinks only.
- **Nothing fires on start**: the first complete arguments of a row (after a start, a restart,
  an edit, `enabled` on, or when the row appears) are its baseline. A call goes out only when
  they change. A row whose arguments hold `null` sends nothing (unless `invoke_allow_null`).
- One call in flight per row and sink; changes meanwhile wait and the newest goes next.
  `throttle_ms` spaces a row's calls. At most 50 calls in flight for the link.
- A failed call counts in `errors` and is logged at `info` (ids only, never values); it is not
  retried (an action is not idempotent).
- The embedded link does not trust its own key: a query cannot write the DQL link's own nodes.

## Bounds

200 queries; 1 000 rows per query by default (5 000 at most); 1 000 lists per query (the host
allows 2 000 per link); 1 000 subscriptions per link; 20 000 cached samples per query; 16
stages and 4 KiB per query text, 1 KiB per expression. Every event of the link spends at most
700 commands; the rest goes on in the next events.

An expression's cost per row is bounded before it runs, on the parsed expression (CEL cannot
be stopped halfway):
- no macro (`map`, `filter`, `all`, `exists`, `exists_one`) inside another macro's body: chain
  them instead (`list.filter(x, …).map(x, …)`), at most 4 in one expression;
- no `+` and no list or map literal inside a macro's body, so each step of a chain gives at most
  what it was given;
- a list literal holds at most 64 items;
- a value of more than 1 000 items (all levels), or a text or bytes value over 16 KiB, is `null`
  in an expression.

## From DSA

`convert_dsa {text, site}` (or `wyrm_dql::dsa::convert`) rewrites a DSA text for one site:

| DSA | WYRM |
|---|---|
| `list /downstream/System/*` | `list wy/<site>/downstream/System/**` |
| `?` | `*` |
| `list *` | `list wy/<site>/downstream/**` |
| `list brokers` | `list sites wy/<site>` |
| `sublist /downstream/?` | `sublist ./downstream/*` |
| `invoke /downstream/Mongo/x/publish(…)` | `invoke wy/<site>/downstream/Mongo/x/~act/publish(…)` |
| `filter …` | kept (turned into CEL) |
| `expression d="row.value * 2"` | kept; it is CEL now (`Math.min` and other JavaScript are not) |

Differences: `like` is SQL's (`%` is any text, the whole value must match; DSA matched
anywhere); DSA's `>=` was always true (a bug) and is a comparison here; a `sublist` parent that
goes takes its rows with it (DSA left them).

## In the terminal

```bash
wyr query "list wy/s/downstream/mock/** | where type == 'number' | subscribe"
```

```bash
wyr query --once --json "list sites wy/central"
```

`--every-ms` paces the printout; sinks are printed, not sent, unless `--sinks`.
