# ADR 0044 — Flow blocks, third set: computation on the server

Status: accepted (2026-11-11, owner request "implement everything that can work
in Rust and on the platform"; decisions delegated under ADR 0029).

## Context

WYRM had 55 node types (ADR 0032, 0038, 0040). Flows on a broker also need
math, text and codecs, time, events, tables and reads of history and of a
node. Everything that is computation, data shaping, time, text, events, state
or a read of the tree belongs on the broker. What needs a screen, a browser,
the editor, a style, a device sensor or a file API does not. This set adds 70
types: `node_types` lists 125.

## Decision

### 1. One block machinery

The new types are logic blocks of `crates/wyrm-flow/src/blocks.rs` (ADR 0032:
a value per parameter, a port `in.<p>` for every parameter that a wire may set,
change-only outputs, the worst quality of the inputs, nothing at start but the
variables; amended 2026-11-11: a pure block with no wired input calculates once
at start, spec 06 0.2.30). Their calculations are pure functions in `blocks/*.rs` with unit
tests. The readers (`load_history`, `get_node`) are kinds of
the reader of ADR 0040 §4 (`readers.rs`): `load_history` and `get_node`.

### 2. Tables

A table is a value:

```json
{"columns": ["name", "kw"], "rows": [{"name": "pump", "kw": 3}, {"name": "fan", "kw": 7}]}
```

- `columns` gives the order; a row is a map. A cell that a row lacks is `null`.
- Every table input also takes a list of maps (the rows of `list_children`, of
  a `split`, of `make_array`): its columns are the keys in the order they first
  appear, sorted within one row (a WYRM map has sorted keys). Rows given as
  lists (`{"columns": […], "rows": [[…]]}`) are taken by position.
- There is no `row` column: a row's index is its position from 0. No table
  gets an index column of its own.
- Bounds: 10 000 rows, 128 columns, a column name of 256 bytes, 512 KiB of
  encoded cells, nesting 32 (spec README rule 6). A table block whose result is
  larger sends `null` with quality `bad`.
- Mutators (`table_add_row`, `table_edit_rows`, `table_remove_rows`) are pure
  transforms of their input: they write into no stored table; in a stream
  engine the output is the next table. A flow that
  keeps a table across samples wires it through `table_recorder` or keeps it in
  broker storage.
- Per-row scripts (`table_filter`, `table_map_columns`, `table_edit_rows`,
  `table_remove_rows`) are rhai over the variables `row` (the row as a map) and
  `index`. A column name is not a variable: names come from the data and the
  compiler checks a script against fixed names. The scripts of one table have
  100 ms in all (past that: `null` and the reason on `error`), each row the
  engine's 10 000 operations.

### 3. Time

- A date value is a number of **microseconds** since the Unix epoch, as `t` of
  every sample, `HistRow.t` and `last_run`. A date input also takes RFC 3339
  text, `yyyy-M-d[ HH:mm[:ss]]`, `yyyy/M/d`, `M/d/yyyy`. Not milliseconds: WYRM
  keeps one unit for all its times.
- Wall time is computed in the zone of the parameter `time_zone`: an IANA name
  (`Europe/Kyiv`), `UTC`, or `±HH:MM`. The default is `UTC`, not the host's
  zone: a broker in a container often has no zone file, and a flow must give
  the same result on every host. The tz data is `jiff`'s bundled tzdb, as in
  `wyrm-schedule`. A wall time in a DST gap moves forward, a repeated one takes
  the earlier instant (as the scheduler).
- A block that depends on the clock (`now`, a relative `date_range`) reads it
  once per calculation through the runtime's clock; the pure functions take
  `now` as an argument, so tests are exact. A relative range is calculated
  again on a clock of 1 s while its input is relative, so `today` rolls over.
- `date_range` takes `week_start` (default `monday`) and `time_zone`;
  `previousN<unit>` is the period before `currentN<unit>`.

### 4. Readers

- `load_history` reads the historian (`~val?history=`, ADR 0014) through
  `WyrmClient::history`: its rows `{t, v, q}` as a table, at most `limit`
  (1 … 10 000) rows. An answer that reached `limit` may have more: the `ok`
  event says `truncated: true` and `rows`, so the cut is never silent. A table
  past 512 KiB is an `error` event with `resource_exhausted`. A query field
  that changes while a read runs reads again after it, never cancels it.
- Several keys merge by time with one `load_history` each (the same `window`)
  and `table_join` on `t`: one key per reader keeps the scope rules as they are.
- `get_node` reads one node's summary and its actions with their parameters.
- Each is a read field in `nodes::read_fields`, so the deployer, every watcher
  and every previewer must read its key or scope, as `load_value` (ADR 0040 §1).
- A reader runs on `dataflows/<id>/~act/trigger {node}` too (Studio §10 item 8):
  the caller must read the reader's key and its scope (level `read`), instead
  of a command target's `max(maxperm, write)`.
- A trigger starts a run that flows on along the edges (security review
  2026-11-11): the caller also needs `max(maxperm, write)` on the target of
  every `set` and `invoke` downstream of the triggered node, found by a walk
  over every edge, transitively, with the custom blocks inlined. A reader with
  no command downstream needs read alone. The same rule holds for a command
  block: a command whose answer runs another command needs the rights of both.

### 5. Stream rules the blocks keep

WYRM is a stream engine: a block calculates on each sample, not on a timer.

- Numbers are integers while they fit, then floats; a result that is not
  finite is `null` (no NaN or Infinity in a WYRM value). There is no NaN
  constant: `const` with `null` stands for it.
- A block calculates on each sample and sends its outputs in its declared
  order; the compiler refuses a cycle that has no `delay`.
- An output goes out when its value or quality changed; events always.
- The catalog's `default` is the effective value.
- A trigger is an event or a value that differs from the last one; a sample
  born at the start never acts (ADR 0040 §2). The same `born` rule covers the
  start of a flow.
- No block panics; a bad input gives `null` (quality `bad` where the input was
  valid but too large).
- `median` of an even count is the mean of the two middle numbers; `date_math`
  counts years, months and days on the calendar of `time_zone`, so a day over
  a DST change keeps the wall time.
- `modulo`'s remainder is never negative, `max`/`min` of no number are `null`,
  `scale` does not clamp, `split` gives a list, `substring` clamps an overrun:
  existing WYRM behaviour that deployed flows rely on.

### 6. Patterns

`case`, `router` and `replace` take `regexp`. A pattern is compiled by the `regex` crate
(linear time, no backreferences) with a compiled-size limit of 64 KiB and at
most 256 bytes of pattern; the input is at most 4 KiB. A pattern that does not
compile matches nothing.

### 7. Left out

- `repeat` (one block instance per table row): the instance count is known
  only at run time, but the 1000-node budget and the deploy proofs are
  computed when the definition is compiled. A later set may bound it by a
  `max_rows` in the config.
- Archive parsing (zip): needs an archive codec with bounds on expansion;
  files reach a flow through the file store links.
- A PID block: it needs a decision on its form and its bounds.
- Error groups without wires: an implicit route between blocks would bypass
  the cycle check, `watch` and `preview`; `catch_error` takes wires.
- Blocks that need a screen, a browser, the editor, a style, a device sensor
  or a file API.

## Amendment 2026-11-11: `now` has a clock (spec 06 0.2.30)

`now` gave the time only on a sample of `in`, and its `in` took a typed
constant. A clock block that shows nothing until something is wired into it is
of no use (owner's screenshot: `today` typed into `in`, no output), and the
value on `in` meant nothing. Now:

- `interval_ms` (port `in.interval_ms`, default 1000; 0: only on samples of
  `in`; else 100 … 86 400 000, as a command's period; a value outside is
  refused in the config and ignored on the port).
- With a period, `now` sends the time once at start, made of constants (it
  runs no command), and then every period; those ticks are ordinary samples,
  as a `timer`'s. A sample of `in` gives the time at once too.
- `in` is only a trigger: it takes no constant (`values: true` is dropped
  from its catalog entry). A `values` saved before is read and ignored, so a
  stored flow still compiles.
- ОБЕРЕЖНО: a `now` stored before 0.2.30 has no `interval_ms`, so after the
  upgrade it also sends every second (the default). Its ticks are ordinary
  samples: a `now` wired to `in` of a `set` or an `invoke`, or to a `trigger`,
  then runs that command every second. Set `interval_ms: 0` to keep the old
  behaviour (only on samples of `in`). No deployed flow of the demo has a
  `now` (checked 2026-11-11).

## Consequences

- `node_types` lists the new types; the catalog gains `display` per parameter
  (spec 06 0.2.29). Studio draws them from the catalog; its follow-up is in the
  pull request.
- The guide (`docs/flow-blocks.md`) has a section per group with fields,
  behaviour and bounds.
