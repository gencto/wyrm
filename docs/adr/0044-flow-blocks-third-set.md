# ADR 0044 — Flow blocks, third set: the reference palette on the server

Status: accepted (2026-11-11, owner request "implement everything that can work
in Rust and on the platform"; decisions delegated under ADR 0029).

## Context

The owner handed over the field reference and the behaviour of every dataflow
block of the reference dashboard product (DGLux5, 152 palette items; the
handoff is kept outside the repository). WYRM had 55 node types (ADR 0032,
0038, 0040). `docs/flow-blocks-coverage.md` maps every palette item to WYRM.
Everything that is computation, data shaping, time, text, events, state or a
read of the tree belongs on the broker. Items that need a screen, a browser,
the editor, a style, a device sensor or the dashboard server's file API do not.

## Decision

### 1. One block machinery

The new types are logic blocks of `crates/wyrm-flow/src/blocks.rs` (ADR 0032:
a value per parameter, a port `in.<p>` for every parameter that a wire may set,
change-only outputs, the worst quality of the inputs, nothing at start but the
variables). Their calculations are pure functions in `blocks/*.rs` with unit
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
- There is no `row` column: a row's index is its position from 0. The
  reference inserts an index column 0 into every table; WYRM does not.
- Bounds: 10 000 rows, 128 columns, a column name of 256 bytes, 512 KiB of
  encoded cells, nesting 32 (spec README rule 6). A table block whose result is
  larger sends `null` with quality `bad`.
- Mutators (`table_add_row`, `table_edit_rows`, `table_remove_rows`) are pure
  transforms of their input: the reference writes back into a table owned by a
  table variable; in a stream engine the output is the next table. A flow that
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
  text, `yyyy-M-d[ HH:mm[:ss]]`, `yyyy/M/d`, `M/d/yyyy`. The reference uses
  milliseconds; WYRM keeps one unit for all its times.
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

### 5. Differences kept against the reference rules R1–R15

WYRM is a stream engine; the reference is a dirty queue drained on a timer.

- R1 (JS doubles): WYRM numbers are integers while they fit, then floats; a
  result that is not finite is `null` (no NaN or Infinity in a WYRM value).
  The reference's NaN constant is `null`.
- R3, R7, R15 (deferred queue, write order, cycle cut in the drain): a block
  calculates on each sample and sends its outputs in its declared order; the
  compiler refuses a cycle that has no `delay`.
- R4 (NaN and new objects always propagate): an output goes out when its value
  or quality changed; events always.
- R8 (registration defaults are placeholders): the catalog's `default` is the
  effective value.
- R10, R10a (trigger windows): a trigger is an event or a value that differs
  from the last one; a sample born at the start never acts (ADR 0040 §2).
- R12 (load drain): the same `born` rule replaces it.
- R14 (an exception aborts the drain): no block panics; a bad input gives
  `null` (quality `bad` where the input was valid but too large).
- `modulo`'s remainder is never negative, `max`/`min` of no number are `null`,
  `scale` does not clamp, `split` gives a list, `substring` clamps an overrun:
  existing WYRM behaviour that deployed flows rely on.

### 6. Patterns

`case`, `router` and `replace` take `regexp`. A pattern is compiled by the `regex` crate
(linear time, no backreferences) with a compiled-size limit of 64 KiB and at
most 256 bytes of pattern; the input is at most 4 KiB. A pattern that does not
compile matches nothing.

### 7. Left out

- `repeater` (one block instance per table row): the instance count is known
  only at run time, but the 1000-node budget and the deploy proofs are
  computed when the definition is compiled. A later set may bound it by a
  `max_rows` in the config.
- `zipParser`: needs an archive codec with bounds on expansion.
- The schema-only `pidloop` (not in the palette): the reference's PID formulas
  are not decoded (two operators of its integral term are unknown); a PID
  block of its own needs a decision on its form and its bounds.
- Error groups of `catchError` without wires: an implicit route between blocks
  would bypass the cycle check, `watch` and `preview`; `catch_error` takes
  wires.
- Everything marked "not for a broker" in the coverage table.

## Consequences

- `node_types` lists the new types; the catalog gains `display` per parameter
  (spec 06 0.2.29). Studio draws them from the catalog; its follow-up is in the
  pull request.
- The guide (`docs/flow-blocks.md`) has a section per group with fields,
  behaviour and bounds.
