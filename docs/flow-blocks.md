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
5. An operand input (`in`, `in.<name>`) can hold a constant: the config key
   `values: {"in.0": 5}` (spec 06 0.2.19). The constant is the input's value
   until a sample on that input replaces it. A constant calculates nothing: the
   block calculates on its first real sample. A parameter's port, `reset` and
   the variables take no constant (a parameter's config is its constant).
6. An output is sent only when its value or its quality changed. Events
   (`on_change`, `on_loop`) are always sent: `{event: <port>, id: <n>}`.
7. Quality is the worst quality among the inputs that have a sample. The time
   is the latest of their times.

УВАГА: an operator does not calculate at start. It waits for its first input,
so a deploy, a hot swap or a restart never fires an `invoke` or a `set` by
itself, and neither does an operand constant. Only the variables (`number`, `string`, `bool`) send their value at
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
| `round` | `in`, `in.precision`, `in.min_precision` | `out`, `text` | Rounded to `precision` places (0 to 20, default 0: an integer). Halves round away from 0. `text` (spec 06 0.2.21): the same number as text with `precision` places, its trailing zeros trimmed down to `min_precision` places (default: `precision`). |
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
| `if` | `in.op`, `in.then`, `in.else`, `in.<inputs>` | `out` | `op`, `then` (default true), `else` (default false), `inputs` |
| `hub` | `in.ignore_null`, `in.<inputs>` | `out`, `index`, `on_change` | `ignore_null` (default true), `inputs` |
| `stopwatch` | `reset`, `in.enabled`, `in.interval`, `in.step`, `in.modulo`, `in.loop`, `in.reset_value` | `out`, `on_loop` | the same names |
| `trace` | `in.tracing`, `in.msg`, `in.<inputs>` | — | `tracing` (default true), `msg` (default `trace`), `inputs` |
| `case` | `in`, `in.op`, `in.else`, `in.<inputs>` (pairs) | `out` | `op` (default `=`), `else` (default null), `inputs` |

`if` sends `then` when the inputs pass `op`, else `else`:

- `=` (default): all inputs are equal; the same number in another form counts
  (`"5"` and `5`);
- `and`, `or`: of the inputs as bools;
- `>`, `<`, `>=`, `<=`: between each input and the next (`in.0 > in.1 > in.2`);
  fewer than two inputs do not pass;
- `!=` (spec 06 0.2.21): the first input equals none of the others;
- `contains`, `starts_with`, `ends_with`: the first input as text with any of
  the others as text (a `null` other never matches).

`case` (spec 06 0.2.21, as the DGLux block) compares `in` with case values and
sends the value paired with the first case that matches, else `else`
(default `null`). Its variable inputs come in pairs: the first of a pair is a
case, the second what it gives. Give them constants in `values`:

```json5
{ type: "case", op: ">=", inputs: ["c1", "v1", "c2", "v2"],
  values: { "in.c1": 90, "in.v1": "high", "in.c2": 10, "in.v2": "normal" },
  else: "low" }
```

`op` is `=`, `!=`, `>`, `<`, `>=`, `<=` (as numbers; `=` and `!=` as `if`'s
`=`), or `contains`, `starts_with`, `ends_with` (as text; an empty case text
matches nothing). An input left without a pair is not used. DGLux's `regexp`
is not here: a pattern from a port could take any time to match.

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
| `concat` | `in.strict`, `in.<inputs>` | `out` | The inputs as one text; a missing input is empty text, or with `strict` the result is `null`. A text longer than 4 KiB is `null` with quality `bad`. |
| `length` | `in` | `out` | The characters of a text, the items of a list, the entries of a map or the bytes of binary; else `null`. |

## Parameter ports of the other node types

The older node types take the parameters an editor binds on a port
`in.<parameter>` too (spec 06 0.2.17), with the rule of the blocks: the config
value (or the default) at start, then the last good sample.

| Type | Parameter ports |
|---|---|
| `scale` | `in.k`, `in.b` (and the range ports `in.input_min` … `in.output_max`) |
| `alarm` | `in.high`, `in.low`, `in.hysteresis`, `in.delay_s`, `in.return_delay_s` |
| `delay` | `in.ms` |
| `window` | `in.size_s` |
| `deadband` | `in.abs`, `in.pct` |
| `timer` | `in.period_ms` |

- Every one of these ports takes a number. A sample that is not a finite
  number, or that is outside the parameter's bounds (`period_ms` at least 10,
  `size_s` above 0, `ms`, `delay_s` and `return_delay_s` at least 0), is
  ignored: the last good value stays.
- The config rules stay: `alarm` still needs `high` or `low` in its config,
  `deadband` `abs` or `pct`. The config gives the start value.
- A new `period_ms`, `ms`, `size_s` or alarm delay takes effect at once. The
  node's clock starts again one period after the change. A sample that a
  `delay` already holds keeps its time.

## A key from a port

`subscribe` and `liveliness` read the key of their config. Their port `in.key`
takes another key while the flow runs (spec 06 0.2.22, ADR 0040 §1): a text
block builds a path, and the path drives the source.

| Type | Inputs | Outputs | Parameters |
|---|---|---|---|
| `subscribe` | `in.key` | `out`, `error` | `key` (the start key; may be absent with a scope), `key_scope` |
| `liveliness` | `in.key` | `out`, `error` | `key`, `key_scope` |

1. Give the node `key_scope`, a key expression of the keys the port may name:
   `downstream/modbus/line1/**`. The compiler refuses an edge into `in.key`
   without it.
2. Deploy. The deployer must read all of the scope. `watch`, `ports` and
   `preview` ask the same of their caller.
3. Send a key to `in.key`: a text, one concrete key inside the scope
   (`downstream/modbus/line1/t1`). A wildcard, a key of another site, a key
   under `sys` and a value that is not a text are refused.

- A new key ends the old read first. `out` is `null` with quality `uncertain`
  until the new key's first sample.
- A refused value reads nothing. `error` carries the reason as a text and goes
  back to `null` with the next good key.
- `null` on the port reads nothing and is no error.
- Two changes are at least 100 ms apart. The latest value wins.
- The output `key` (the parameter's echo) is the key in use.
- `liveliness` sends nothing for a node that has no token, as before.

УВАГА: the targets of `set` and `invoke` have no port. A flow changes what it
writes and the arguments of an action, never where it writes (ADR 0040 §1a).

## The action block and the command behaviours

`invoke` is the action block: an action of a node, dropped from the tree. `set`
writes a point. Both are commands, and both have the same behaviour fields
(spec 06 0.2.23, ADR 0040 §2).

| Type | Inputs | Outputs | Parameters |
|---|---|---|---|
| `invoke` | `in`, `trigger`, `in.interval_ms`, `in.auto_run`, `in.enabled`, `arg.<name>` | `out`, `result`, `sent`, `ok`, `error`, `running`, `last_run` | `path`, `action`, `args`, `on`, `allow_bad`, `interval_ms` (default 0), `auto_run` (default false), `enabled` (default true) |
| `set` | `in`, `trigger`, `in.interval_ms`, `in.auto_run`, `in.enabled` | `sent`, `ok`, `error`, `running`, `last_run` | `path`, `on`, `deadband`, `allow_bad`, `interval_ms` (default 0), `auto_run` (default true), `enabled` (default true) |

Arguments of `invoke`:

1. Each key of `args` is one argument. Its value is the argument's constant:
   `args: {setpoint: 21.5, mode: "auto"}`.
2. Each argument has the port `arg.<name>`. A sample there replaces the
   constant. Use `null` as the constant of an argument that only a wire gives.
3. `"$in"` as a constant stands for the last value on `in`.

What runs a command:

| Cause | `invoke` | `set` |
|---|---|---|
| a sample on `in` | every sample that passes `on` | the value, when `auto_run` is true and it passes `on`/`deadband` |
| `trigger` | an event, or a value that differs from the last one | the same: it writes the value that `in` holds |
| `auto_run` | a sample on `arg.<name>` that changes the argument | see `in` |
| `interval_ms` above 0 | every period | every period: the held value again |
| the action `dataflows/<id>/~act/trigger {node}` | one run | one write of the held value |

- `enabled: false` stops every cause.
- `interval_ms` is 0 (off) or 100 … 86 400 000. A period is skipped while the
  run before it has not answered.
- `sent` fires when the request leaves, `ok` when the target answered, `error`
  when it refused: `{event: "error", id, code, message}` with the status code
  of spec 04. `running` is true between the two. `last_run` is the time of the
  last `sent` in microseconds.
- `invoke.result` is the last result. `invoke.out` stays: the result, or the
  error text with quality `bad`.

УВАГА: a deploy, a hot swap, a reload and a restart never run a command through
`trigger`, `auto_run` or `interval_ms`. A value that exists because the flow
started (a variable's start value, a `const`, a parameter's echo, a timer's
first tick, the first sample of a `subscribe`) only fills the field. The first
run of `interval_ms` is one full period after the start. `in` does not have
this rule: a variable wired to `in` of a `set` or an `invoke` still acts at
deploy. Wire `trigger` where a deploy must do nothing.

The `trigger` action is the block's button in the editor. It needs level
`write` on the flow, and the caller needs `write` on the block's own target
(the flow's `maxperm` when that is higher).
It works on a deployed flow that runs. In a preview a command block shows what
it would send (`sinks`), fires `sent`, and never `ok` or `error`.

## Fields as outputs

Every field of a node is also an output (ADR 0038, spec 06 0.2.15). This
applies to every node type, not only to the blocks.

- A parameter `p` is an output `p`. It sends the parameter's effective value:
  the config value or the default, replaced by the last sample on `in.<p>`
  where that port exists. It sends once when the node starts and then on every
  change. A `stopwatch` that stops at `modulo` sends `enabled` false.
- An input `x` that is not a parameter's port is an output `x`. It repeats every
  sample on `x`, before the node handles it.
- The output has the field's name: `["scale1.input_min", "add1.in.0"]` reads the
  parameter `input_min` of `scale1`; `["if1.in.0", "show.in"]` repeats the
  input `in.0` of `if1`.
- A declared output keeps its name. An input's echo comes before a parameter's:
  `latch` has the input `reset` and the parameter `reset`, so its parameter has
  no output.
- Types: an input's echo has the input's type. A parameter's echo is `number`,
  `bool` or `map` as the parameter, else `any`.
- An echo output with no edge is never built and costs nothing.

УВАГА: a parameter's echo sends at start. An edge from it to an `invoke` or a
`set` runs that command when the flow is deployed, restarted or hot-swapped.
This is the one way a block fires a command by itself.

The catalog (`dataflows/~act/node_types`) tells an editor which field is
which: per parameter `port` (`in.<p>` when it has one), `default` (typed: a
number stays a number) and `echo`; per type `port_types` and `echo_inputs`.

An editor shows the live values of a deployed flow with
`dataflows/<id>/~act/watch` (spec 06, "Живі значення"). The engine keeps the
last sample of every port from the start (spec 06 0.2.18), so a variable that
sent its value once at deploy shows in every later snapshot and in `ports`.

An editor shows the live values of a draft that is not deployed with
`dataflows/~act/preview {def}` (spec 06 0.2.16, ADR 0038 §5). The draft runs
in a sandbox: nothing is stored, and `set`, `invoke` and `publish` write
nothing. The rows are those of a watch, plus `sinks`: what each of these nodes
would write, and where. The first row already has the variables' start values.
A preview ends after 10 minutes; the editor opens it again with its latest
draft.

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
(`fieldsOf`, `fieldLabel`, `isVariable`, `tailParams`).

**One field = one entity (owner decision 2026-11-08, as DGLux).** A field's
value, its binding and what it feeds are one row, never three:

- a field `p` of a block is the parameter `p` ∪ its input `in.<p>` ∪ its
  echo output `p` (ADR 0038 §1);
- the main value of a variable block (`number`, `string`, `bool`, `const`:
  input `in`, parameter `value`, output `out`) is ONE field `Value`;
- an operand (`in`, `in.0`, `in.1`, … that is no parameter's port) is a field
  with both ports: its input and its echo;
- a result (`out`, `quotient`, `remainder`, …) is a field with a right port
  only.

Binding INTO a field is an edge to its engine input (`in.<p>`; `in` for a
variable's `Value`, an operand's own port); binding OUT of a field is an edge
from its echo or output (`out` for a variable's `Value`, `p` for a
parameter). Older definitions that wired a variable's echoes `value` or `in`
still draw on the `Value` row; a new binding uses `out`.

Rules:

1. A row reads a human label: the catalog's `display`, else an override,
   else sentence case with a unit suffix in brackets. Numbered inputs `in.0`,
   `in.1` read `Input 1`, `Input 2`. Names a user or a device gave (points,
   `expression` variables, `wasm` ports, `invoke` arguments) stay as given.
   The engine name is the row's tooltip and stands under the label in the
   inspector.
2. Ports: `⇄` a left port (the engine has an input for the field) and a
   right port (its echo or output); `→` a right port only; `←` a left port
   only.
3. Order: fixed operands, then the parameters, then the variable inputs,
   then the parameters DGLux draws after them (`tailParams`: `if` then,
   else; `concat` strict; `hub` ignore null), then the results. A sink names
   what it writes before the value.
4. A parameter is a row of the block when it has a port, belongs to the form
   in use, is set, has a default, is required, or is one of a pair the engine
   needs one of (`deadband` `abs`/`pct`, `alarm` `high`/`low`). Maps, lists
   and the list of variable inputs (`inputs`) are edited in the inspector
   only.
5. In the inspector a parameter with `choices` is a dropdown, a `bool` a
   toggle, anything else a text field typed as the parameter's type (a
   number, text, JSON).
6. **A bound field shows the value that comes in along its wire, never the
   path** (accent colour on the block; read only, framed, with a `bound` mark
   in the inspector). The wire and the source row light when the pointer is
   over the field; the inspector's link menu has `Go to source` and
   `Unbind`. A bound field with nothing known yet shows nothing, not the
   typed value the binding replaces.
7. An operand of a type with catalog `values: true` holds a typed value:
   the node's config `values: {"<port>": <value>}` (spec 06 0.2.19). A
   binding replaces it; the typed value stays in the config and returns on
   unbind. Never on a parameter's port, `stopwatch.reset` or a variable's
   `in`. `case` reads its variable inputs as pairs: `Case 1`, `Then 1`, …
8. Values are live. A draft that runs otherwise than the deployed version
   (its layout aside) runs as a preview (`dataflows/~act/preview`): the
   blocks show its values and each sink what it would write (`would write
   70.7`, a `preview` tag; nothing is written). A draft equal to the
   deployed version shows the watch's values (`dataflows/<id>/~act/watch`).
   Where neither has a sample the editor follows the wire back to its
   source field: a variable's or a parameter's typed value, a point's tree
   value.
9. Sinks (`publish`, `set`, `invoke`) show no echo outputs of their
   parameters (the engine has them; the editor leaves them out so a sink
   stays a sink). A `set` repeats what it writes on its point's row.

| Type | Fields on the block, in order | Field ← engine | Inspector only | Editors | Engine gap against the DGLux block |
|---|---|---|---|---|---|
| `number`, `string`, `bool` | Value ⇄ | Value = `in` → `value` → `out` | — | number box; text (`string`: multi-line in DGLux); toggle | none: DGLux has the one field `value` |
| `const` | Value → | Value = `value` → `out` | — | JSON or text | no input (sent once at start) |
| `subscribe` | Point ⇄ · `<point>` → · Error → | `in.key` → `key`; the point's value on `out`; `error` | Scope (`key_scope`) | Point: a tree picker; bound: a wire | none (spec 06 0.2.22) |
| `liveliness` | Node ⇄ · `<node>` → · Error → | `in.key` → `key`; `out`; `error` | Scope (`key_scope`) | as `subscribe` | none (spec 06 0.2.22) |
| `timer` | Period (ms) ⇄ · Count → | `in.period_ms` → `period_ms`; `out` | — | — | none (spec 06 0.2.17) |
| `expression` | Expression → · Trigger → · Quality → · `<name>` ⇄ … · Output → | `in.<name>` ⇄ | Inputs (list) | Trigger, Quality dropdowns | `expr`, `trigger`, `quality` have no input |
| `filter` | Input ⇄ · Expression → · Output → | `in`; `expr` | — | — | `expr` has no input |
| `latch` | Input ⇄ · Reset ⇄ · Reset mode · Output → | `in`, `reset` (operands); `reset` parameter (no echo: the input took the name) | — | Reset mode dropdown | parameter `reset` has no input and no echo |
| `delay` | Input ⇄ · Delay (ms) ⇄ · Output → | `in`; `in.ms` → `ms` | — | — | DGLux `delay` has `mode` |
| `scale`, form `k × in + b` | Input ⇄ · Factor ⇄ · Offset ⇄ · Output → | `in`; `in.k` → `k`, `in.b` → `b`; `out` | Form | Form dropdown | none (spec 06 0.2.17) |
| `scale`, form `Range` | Input ⇄ · Input min ⇄ · Input max ⇄ · Output min ⇄ · Output max ⇄ · Output → · Input out of range → | `in.input_min` → `input_min`, … | Form | Form dropdown | none (DGLux: the same six fields) |
| `deadband` | Input ⇄ · Absolute change ⇄ · Percent change ⇄ · Output → | `in`; `in.abs` → `abs`, `in.pct` → `pct` | — | — | none (spec 06 0.2.17) |
| `window` | Input ⇄ · Size (s) ⇄ · Kind → · Function → · Max samples → · Output → | `in`; `in.size_s` → `size_s`; the others config only | — | Kind, Function dropdowns | `kind`, `fn`, `max_samples` have no input |
| `alarm` | Input ⇄ · High ⇄ · Low ⇄ · Hysteresis ⇄ · Delay (s) ⇄ · Return delay (s) ⇄ · On bad quality → · Active → · Event → | `in`; `in.high` → `high`, `in.low`, `in.hysteresis`, `in.delay_s`, `in.return_delay_s`; `on_bad` config only | — | On bad quality dropdown | `on_bad` has no input |
| `publish` | Value name · Value ← | `in` | Meta | — | — |
| `set` | `<point>` ⇄ · Trigger ⇄ (unbound: a button, `~act/trigger`) · Interval (ms) ⇄ · Auto run ⇄ · Enabled ⇄ · Sent → · Ok → · Error → · Running → · Last run → | `in` → its echo `in`; `trigger`; `in.<p>` → `<p>` (spec 06 0.2.23) | Point (`path`), Write on, Deadband, Allow bad quality | Write on dropdown; toggle | — |
| `invoke` | Trigger ⇄ (unbound: a button, `~act/trigger`) · Run when ← · Action · `<argument>` ⇄ … · Interval (ms) ⇄ · Auto run ⇄ · Enabled ⇄ · Result → · Sent → · Ok → · Error → · Running → · Last run → | `trigger`; `in`; `arg.<name>` ⇄ (constant in `args`); `in.<p>` → `<p>`; `result`, `out` (spec 06 0.2.23) | Node (`path`), Args, Allow bad quality | Run on dropdown; toggle | arguments are config only, not fields with inputs |
| `wasm` | Artifact → · `<input>` ⇄ … · `<output>` → … | ports named by `inputs`/`outputs` | Config, Fuel, Memory (MB) | — | — |
| `add`, `subtract`, `multiply`, `divide`, `max`, `min` | Input 1 ⇄ · Input 2 ⇄ · … · Output → (− / +, at least 2) | `in.0`, `in.1`, …; `out` | — | operands typed (`values`) | none (spec 06 0.2.19: an operand holds a typed value) |
| `abs`, `not`, `length` | Input ⇄ · Output → | `in`; `out` | — | `in` typed (`values`) | none |
| `round` | Input ⇄ · Precision ⇄ · Min precision ⇄ · Output → · Text → | `in`; `in.precision` → `precision`, `in.min_precision` → `min_precision`; `out`, `text` | — | `in` typed (`values`) | none (spec 06 0.2.21: `text` is DGLux's text result) |
| `modulo` | Input ⇄ · Modulo ⇄ · Quotient → · Remainder → | `in`; `in.modulo` → `modulo` | — | — | — |
| `if` | Operation ⇄ · Input 1 ⇄ · Input 2 ⇄ · … · Then ⇄ · Else ⇄ · Output → | `in.op` → `op`; `in.<n>`; `in.then` → `then`, `in.else` → `else` | — | Operation dropdown (`=`, `!=`, `and`, `or`, `>`, `<`, `>=`, `<=`, `contains`, `starts_with`, `ends_with`); operands typed | none (spec 06 0.2.20, 0.2.21) |
| `case` | Input ⇄ · Operation ⇄ · Case 1 ⇄ · Then 1 ⇄ · … · Else ⇄ · Output → (− / + by a pair, at least one) | `in`; `in.op` → `op`; pairs `in.<n>` by position; `in.else` → `else`; `out` | — | Operation dropdown; cases and thens typed (`values`) | `regexp` left out (spec 06 0.2.21) |
| `hub` | Input 1 ⇄ · Input 2 ⇄ · … · Ignore null ⇄ · Output → · Index → · On change → | `in.<n>`; `in.ignore_null` → `ignore_null`; outputs | — | Ignore null toggle; operands typed | none |
| `stopwatch` | Reset ⇄ · Enabled ⇄ · Interval (s) ⇄ · Step ⇄ · Modulo ⇄ · Loop ⇄ · Reset value ⇄ · Output → · On loop → | `reset`; `in.<p>` → `p` | — | Enabled, Loop toggles | — |
| `trace` | Tracing ⇄ · Message ⇄ · Input 1 ⇄ · Input 2 ⇄ · … | `in.tracing` → `tracing`, `in.msg` → `msg`; `in.<n>` | — | Tracing toggle; operands typed | none |
| `concat` | Input 1 ⇄ · Input 2 ⇄ · … · Strict ⇄ · Output → | `in.<n>`; `in.strict` → `strict`; `out` | — | Strict toggle; inputs typed (`values`) | no separator (none in DGLux either) |

The editor takes the ports from the catalog (a parameter's `port`), so a
port the engine adds shows without an editor change. Parameters the engine
has no input for show no left port, and a wire dragged onto them is refused
with `<field> takes no input: type its value`. Today these are `expression`
`expr`, `trigger`, `quality`; `filter` `expr`; `latch` its
parameter `reset`; `window` `kind`, `fn`, `max_samples`; `alarm` `on_bad`;
and the sinks' parameters (`crates/wyrm-flow/src/catalog.rs`).
