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
the variable's type, and goes out when it differs.

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
| `concat` | `in.<inputs>` | `out` | The inputs as one text; a missing input is empty text, or with `strict` the result is `null`. |
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
