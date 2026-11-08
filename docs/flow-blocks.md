# Logic blocks in dataflows

Logic blocks are node types of a dataflow (`dataflows/<id>/~def`, spec 06) for
small calculations: variables, arithmetic, comparisons, a hub, a stopwatch and
text. They sit beside `expression`, `scale`, `window` and the other node types,
and the editor shows them in its palette (`dataflows/~act/node_types`).
ADR 0032 records the rules below.

## How a block works

1. A block keeps the last sample of each input port.
2. A parameter has a value from the node's config (or its default). Where the
   block has the port `in.<parameter>`, a sample there replaces that value.
3. Blocks with variable inputs take the config list `inputs` (default
   `["0", "1"]`, at most 64 names `[A-Za-z0-9_]+`). Each name is a port
   `in.<name>`. A name may not be a parameter's name.
4. Any sample on an input calculates the block.
5. An output is sent only when its value or its quality changed. Events
   (`on_change`, `on_loop`) are always sent: `{event: <port>, id: <n>}`.
6. Quality is the worst quality among the inputs that have a sample. The time
   is the latest of their times.

УВАГА: an operator does not calculate at start. It waits for its first input,
so a deploy, a hot swap or a restart never fires an `invoke` or a `set` by
itself. Only the variables (`number`, `string`, `bool`) send their value at
start, as `const` does.

## Numbers and conversions

- A number stays an integer while the result fits: `add`, `subtract`,
  `multiply`, `abs`, `round` to 0 places and `modulo`'s quotient. On an
  overflow the result is a float.
- `divide` always gives a float.
- A result that is not finite (a division by 0, an overflow of a float) is
  `null`.
- Text that parses is a number (`" 5 "` → 5, `"2.5"` → 2.5). `true` is 1 and
  `false` is 0. Other values are not numbers and are left out of a sum or a
  product.
- As a bool: a number is true unless it is 0. Text is false when it is
  `false`, empty or `0`, else true. `null` is false. A list or a map is true.

## The blocks

Parameter names are snake_case, as every other node type's.

### Variables

| Type | Inputs | Outputs | Parameters |
|---|---|---|---|
| `number` | `in` | `out` | `value` (default 0) |
| `string` | `in` | `out` | `value` (default empty) |
| `bool` | `in` | `out` | `value` (default false) |

A variable sends `value` at start. A sample on `in` replaces it, converted to
the variable's type, and goes out when it differs. A `string` longer than 4 KiB
is `null`.

### Math

| Type | Inputs | Outputs | What it gives |
|---|---|---|---|
| `add` | `in.<inputs>` | `out` | The sum; no number at all gives 0. |
| `subtract` | `in.<inputs>` | `out` | The first minus the others; no number gives `null`. |
| `multiply` | `in.<inputs>` | `out` | The product; no number gives `null`. |
| `divide` | `in.<inputs>` | `out` | The first divided by the others, as a float. |
| `max`, `min` | `in.<inputs>` | `out` | The largest or the smallest number. |
| `abs` | `in` | `out` | The absolute value. |
| `round` | `in`, `in.precision` | `out` | Rounded to `precision` places (0 to 20, default 0: an integer). Halves round away from 0. |
| `modulo` | `in`, `in.modulo` | `quotient`, `remainder` | The quotient as a whole number toward 0, and a remainder that is never negative (`-7` by `3`: `-2` and `2`). By 0: both `null`. |
| `scale` | `in`, `in.input_min`, `in.input_max`, `in.output_min`, `in.output_max` | `out`, `input_out_of_range` | See below. |

`scale` is `k × in + b` (defaults 1 and 0). When one of `input_min`,
`input_max`, `output_min`, `output_max` is set in the config or arrives on its
port, `in` is first mapped from `input_min`…`input_max` to
`output_min`…`output_max` (defaults 0, 1, 0, 100), and `input_out_of_range`
says whether `in` was outside the input range. A `scale` without them stays
linear, as before.

### Logic

| Type | Inputs | Outputs | Parameters |
|---|---|---|---|
| `not` | `in` | `out` | — |
| `if` | `in.then`, `in.else`, `in.<inputs>` | `out` | `op`, `then` (default true), `else` (default false), `inputs` |
| `hub` | `in.<inputs>` | `out`, `index`, `on_change` | `ignore_null` (default true), `inputs` |
| `stopwatch` | `reset`, `in.enabled`, `in.interval`, `in.step`, `in.modulo`, `in.loop`, `in.reset_value` | `out`, `on_loop` | the same names |
| `trace` | `in.<inputs>` | — | `tracing` (default true), `msg` (default `trace`), `inputs` |

`if` sends `then` when the inputs pass `op`, else `else`:

- `=` (default): all inputs are equal; the same number in another form counts
  (`"5"` and `5`);
- `and`, `or`: of the inputs as bools;
- `>`, `<`, `>=`, `<=`: between each input and the next (`in.0 > in.1 > in.2`);
  fewer than two inputs do not pass.

`hub` sends the input that changed last: its value on `out` (also when it is
the same value as before), its place in `inputs` on `index`, and an event on
`on_change`. With `ignore_null`, a `null` is not passed.

`stopwatch` counts while `enabled`:

1. Every `interval` seconds (at least 0.05; its clock ticks every 50 ms) it
   adds `step` to the count and sends it on `out`.
2. With `modulo` above 0, a count that reaches `modulo` starts again from the
   remainder and sends an event on `on_loop`. With `loop` false it stops at
   `modulo` and switches itself off until `enabled` comes again.
3. Any sample on `reset` sets the count to `reset_value` and sends it at once.
4. A hot swap keeps the count.

`trace` writes `msg` and the values of its inputs to the broker log.

ОБЕРЕЖНО: `trace` writes at the level `trace` only, as every log line that
holds values. Set the broker's `sys/log_level` to `trace` to see its lines,
and set it back after.

### Text

| Type | Inputs | Outputs | What it gives |
|---|---|---|---|
| `concat` | `in.<inputs>` | `out` | The inputs as one text; a missing input is empty text, or with `strict` the result is `null`. A text longer than 4 KiB is `null` with quality `bad`. |
| `length` | `in` | `out` | The characters of a text, the items of a list, the entries of a map or the bytes of binary; else `null`. |

## Example

A tank level in percent, on a flow value, and a high alarm at 90 %:

```json5
{
  id: "tank", version: 1,
  nodes: {
    raw:   { type: "subscribe", key: "downstream/plc/tank/level_raw" },
    pct:   { type: "scale", input_max: 4095 },
    whole: { type: "round" },
    high:  { type: "if", op: ">", then: "high", else: "ok" },
    limit: { type: "number", value: 90 },
    show:  { type: "publish", node: "level" },
    state: { type: "publish", node: "state" },
  },
  edges: [
    ["raw.out", "pct.in"], ["pct.out", "whole.in"], ["whole.out", "show.in"],
    ["whole.out", "high.in.0"], ["limit.out", "high.in.1"], ["high.out", "state.in"],
  ],
}
```

## How the editor shows each block

WYRM Studio's flow editor draws a block as **fields**, one row each
(`studio/docs/design/specs/flow-editor.md` §3). It builds them from the
catalog (`dataflows/~act/node_types`) in `studio/business/lib/wyrm/mappers/flow_fields.dart`
(`fieldsOf`, `fieldLabel`). The rules:

1. A row reads a human label (owner decision 2026-11-08): the catalog's
   `display`, else an override, else sentence case with a unit suffix in
   brackets. Numbered inputs `in.0`, `in.1` read `Input 1`, `Input 2`. Names a
   user or a device gave (points, `expression` variables, `wasm` ports,
   `invoke` arguments) stay as given. The engine name is the row's tooltip and
   stands under the label in the inspector.
2. Ports: `⇄` a left port (the engine has an input for the field) and a right
   port (its echo or its output); `→` a right port only; `←` a left port only.
   Every field is also an output named like it (ADR 0038 §1): declared
   outputs keep their names, then inputs take theirs, then parameters.
3. A parameter is a row of the block when it has a port, belongs to the form
   in use, is set, has a default, is required, or is one of a pair the engine
   needs one of (`deadband` `abs`/`pct`, `alarm` `high`/`low`). Maps, lists
   and the parameters of the variable inputs (`inputs`) are edited in the
   inspector only.
4. In the inspector a parameter with `choices` is a dropdown, a `bool` a
   toggle, anything else a text field (numbers and JSON typed as the
   parameter's type). A bound field shows its source; an output its value and
   where it goes.
5. Sinks (`publish`, `set`, `invoke`) show no echo outputs of their
   parameters (the engine has them; the editor leaves them out so a sink stays
   a sink). A `set` repeats what it writes on its point's row.
6. Values are live for the deployed version (`dataflows/<id>/~act/watch`).
   Where the watch has no sample yet the editor shows what is known: a wired
   input its source's value, a variable its `value`, a `publish` input what it
   last published.

| Type | Rows on the block, in order | Inspector only | Choices (dropdown) / toggles | Variable inputs | Changed 2026-11-08 |
|---|---|---|---|---|---|
| `subscribe` | `<point>` → (live value of the point) | Point (`key`) | — | — | label is the point's name |
| `liveliness` | `<node>` → | Point (`key`) | — | — | as `subscribe` |
| `timer` | Period (ms) → · Count → | — | — | — | `out` reads `Count` |
| `const` | Value → · Output → | — | — | — | labels |
| `expression` | Expression → · Trigger → · Quality → · `<name>` ⇄ … · Output → | Inputs (list) | Trigger `any`/`all`; Quality `worst`/`ignore`/`custom` | `in.<name>`, names as given, − / + | labels |
| `filter` | Input ⇄ · Expression → · Output → | — | — | — | labels |
| `latch` | Input ⇄ · Reset ⇄ · Reset mode · Output → | — | Reset mode `manual`/`auto` | — | the input `reset` has its echo (was missing); the parameter reads `Reset mode` |
| `delay` | Input ⇄ · Delay (ms) → · Output → | — | — | — | labels |
| `scale`, form `k × in + b` | Input ⇄ · Factor → · Offset → · Output → | Form | Form | — | form chosen in the inspector; no range rows; Factor and Offset have no left port |
| `scale`, form `Range` | Input ⇄ · Input min ⇄ · Input max ⇄ · Output min ⇄ · Output max ⇄ · Output → · Input out of range → | Form | Form | — | range rows only in this form; switching drops the other form's config and wires |
| `deadband` | Input ⇄ · Absolute change → · Percent change → · Output → | — | — | — | `abs`, `pct` on the block (one is required) |
| `window` | Input ⇄ · Size (s) → · Kind → · Function → · Max samples → · Output → | — | Kind `tumbling`/`sliding`; Function `avg`…`rate` | — | labels |
| `alarm` | Input ⇄ · High → · Low → · Hysteresis → · Delay (s) → · Return delay (s) → · On bad quality → · Active → · Event → | — | On bad quality `hold`/`clear`/`raise` | — | `high`, `low` on the block; `out` reads `Active` |
| `publish` | Value name · Value ← | Meta | — | — | labels; live value from `dataflows/<id>/nodes/<node>` |
| `set` | `<point>` ⇄ | Point (`path`), Write on, Deadband, Allow bad quality | Write on `change`/`any`; Allow bad quality toggle | — | labels |
| `invoke` | Run when ← · Action · Run on · `<argument>` … · Result → | Node (`path`), Args, Allow bad quality | Run on `any`/`rising`/`falling`/`change`; Allow bad quality toggle | — | `out` reads `Result`; Allow bad quality off the block |
| `wasm` | Artifact → · `<input>` ⇄ … · `<output>` → … | Config, Fuel, Memory (MB) | — | ports named by `inputs`/`outputs`, as given | labels |
| `number`, `string`, `bool` | Input ⇄ · Value → · Output → | — | `bool` Value toggle | — | labels; Output shows `value` until the first sample |
| `add`, `subtract`, `multiply`, `divide`, `max`, `min` | Input 1 ⇄ · Input 2 ⇄ · … · Output → | — | — | `in.0`, `in.1`, …, − / + (at least 2) | `in.0` reads `Input 1` |
| `abs`, `not`, `length` | Input ⇄ · Output → | — | — | — | labels |
| `round` | Input ⇄ · Precision ⇄ · Output → | — | — | — | labels |
| `modulo` | Input ⇄ · Modulo ⇄ · Quotient → · Remainder → | — | — | — | labels |
| `if` | Operation → · Then ⇄ · Else ⇄ · Input 1 ⇄ · Input 2 ⇄ · … · Output → | — | Operation `=`, `and`, `or`, `>`, `<`, `>=`, `<=` | − / + | labels |
| `hub` | Ignore null → · Input 1 ⇄ · Input 2 ⇄ · … · Output → · Index → · On change → | — | Ignore null toggle | − / + | labels |
| `stopwatch` | Reset ⇄ · Enabled ⇄ · Interval (s) ⇄ · Step ⇄ · Modulo ⇄ · Loop ⇄ · Reset value ⇄ · Output → · On loop → | — | Enabled, Loop toggles | — | labels |
| `trace` | Tracing → · Message → · Input 1 ⇄ · Input 2 ⇄ · … | — | Tracing toggle | − / + | labels |
| `concat` | Strict → · Input 1 ⇄ · Input 2 ⇄ · … · Output → | — | Strict toggle | − / + | labels |

Parameters the editor would bind but the engine has no input for (they show
no left port, and a wire dragged onto them is refused with `<field> takes no
input`): `scale` `k`, `b`; `alarm` `high`, `low`, `hysteresis`, `delay_s`,
`return_delay_s`; `delay` `ms`; `window` `size_s`; `deadband` `abs`, `pct`;
`timer` `period_ms`; `latch` `reset` (ADR 0038 §5 adds them one by one).
