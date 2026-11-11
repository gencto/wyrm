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
matches nothing), or `regexp` (spec 06 0.2.28: a bounded pattern, see "Text
and codecs"). An input left without a pair is not used.

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

### The second set (spec 06 0.2.25, ADR 0040 §4)

Every parameter below has the port `in.<parameter>`.

| Type | Inputs | Outputs | Parameters and what it gives |
|---|---|---|---|
| `substring` | `in` | `out` | `start` (default 0), `length` (default: to the end), counted in characters. |
| `replace` | `in` | `out` | `from`, `to`: every `from` in the text becomes `to`. Plain text, no pattern. An empty `from` replaces nothing. |
| `split` | `in` | `out` | `separator` (default `,`): a list of texts, at most 1000. An empty separator gives one item. |
| `join` | `in` (a list) | `out` | `separator` (default `,`): the items as one text. |
| `make_object` | `in.<inputs>` | `out` | A map: each input's name is a key. Use it for a map argument of an action. |
| `make_array` | `in.<inputs>` | `out` | A list of the inputs, in their order. |
| `get` | `in` | `out` | `path` (default empty): the value at `a.b.0` inside a map or a list; a number is an index. `null` when it is not there. |
| `stats` | `in` (a list) | `min`, `max`, `avg`, `sum`, `count` | The numbers of the list. An empty list gives `count` 0 and `null` for the others. |
| `changed` | `in` | `on_change` | An event when `in` differs from the sample before. The first sample only starts it. |
| `rising_edge` | `in` | `on_edge` | An event when `in` becomes true. Nothing before counts as false. |
| `falling_edge` | `in` | `on_edge` | An event when `in` becomes false after it was true. |
| `counter` | `in`, `reset` | `out` | `step` (default 1), `initial` (default 0): each sample on `in` adds `step`; a true `reset` goes back to `initial`. |
| `toggle` | `in`, `reset` | `out` | `initial` (default false): each sample on `in` flips the bool. |
| `sample_and_hold` | `in`, `trigger` | `out` | The value `in` has when a sample comes on `trigger`. |
| `select` | `in.<inputs>` | `out` | `index` (default 0): the input at that position, from 0; `null` when there is none. |
| `debounce` | `in` | `out` | `ms` (default 500): the last value, once `ms` passed without another. |
| `throttle` | `in` | `out` | `ms` (default 500): the first value at once, then the latest at the end of each period. |

- A text result longer than 4 KiB, and a `split` of more than 1000 parts, is
  `null` with quality `bad`.
- `changed`, `rising_edge`, `falling_edge`, `counter`, `toggle` and
  `sample_and_hold` do not act on a value that exists because the flow started
  (a variable's start value, the first sample of a `subscribe`). Such a value
  only gives the block where it starts from. So these blocks are safe in front
  of a `trigger`.
- `counter` and `toggle` keep their state across a hot swap.
- A number that is not finite (NaN, infinity) is no number for a block. On a
  parameter's port it is ignored, and the last good value stays.
- `debounce` and `throttle` send their value at most a quarter of `ms` late
  (5 to 50 ms).

Readers:

| Type | Inputs | Outputs | Parameters |
|---|---|---|---|
| `load_value` | `trigger`, `in.key`, `in.interval_ms`, `in.auto_run`, `in.enabled` | `out`, `ok`, `error`, `running`, `last_run` | `key`, `key_scope`, `interval_ms` (default 0), `auto_run` (default true), `enabled` (default true) |
| `list_children` | `trigger`, `in.path`, `in.interval_ms`, `in.auto_run`, `in.enabled` | `out`, `ok`, `error`, `running`, `last_run` | `path`, `path_scope`, `interval_ms`, `auto_run`, `enabled` |

- `load_value` reads the stored value of a point once. `out` carries it with
  its quality and time. A point without a stored value gives `error` with
  `not_found`.
- `list_children` gives a list of rows, one per child:
  `{name, path, type, display, is, unit, writable, has_children}` (`type`,
  `display`, `is` and `unit` only where the child has them). At most 1000 rows.
  The deployer, and whoever watches the flow, must read the children
  (`<path>/*`) as well as the node: one child that is denied refuses the block.
- `auto_run` reads at the start and when the key changes. A read is no command,
  so it may run at deploy. `trigger` reads on an event or a changed value;
  `interval_ms` reads every period.
- `key` and `path` take another key on their port inside `key_scope` or
  `path_scope`, as `subscribe` does (see "A key from a port"). A refused key is
  an `error` event with `invalid_parameter`.

## The third set (spec 06 0.2.28, ADR 0044)

These blocks mirror the computation blocks of the reference dashboard product
(`docs/flow-blocks-coverage.md` maps all of its 152 palette items). Every
parameter has the port `in.<parameter>`, except `inputs`, a scope and a rhai
script. The rules of "How a block works" apply: change-only outputs, the worst
quality, nothing at start but a variable or a `constant`.

### Math, rounding and number formatting

| Type | Inputs | Outputs | Parameters and what it gives |
|---|---|---|---|
| `constant` | — | `out` | `name` (default `pi`; `e`, `sqrt2`, `ln2`, `ln10`, `log2e`, `log10e`). Sent at start, as a variable. |
| `factorial` | `in` | `out` | `n!` of the whole part of `in`. Below 1: 1. An integer up to 20!, a float up to 170!, above that `null`. |
| `log` | `in` | `out` | `base` (default 10). `in` at most 0: `null`. |
| `power` | `in` | `out` | `exponent` (default 2). An integer stays an integer while it fits. |
| `root` | `in` | `out` | `degree` (default 2). A negative `in` has a root for an odd whole degree (−8, 3: −2); else `null`. An exact root is a whole number (27, 3: 3). |
| `bound` | `in` | `input_out_of_range`, `out` | `min`, `max` (none: that side is open). `max` applies first, then `min`, so `min` wins when it is above `max`. |
| `round_up`, `round_down` | `in` | `out`, `text` | `precision` (0…20, default 0). `text` has exactly `precision` places. |
| `format_number` | `in` | `out` | `format` (default `#,##0.###`), `decimal_separator` (default `.`), `group_separator` (default `,`). |
| `parse_number` | `in` | `out` | The first number in a text: `abc12.5kg` → 12.5, `1,234.5` → 1234.5 (commas dropped), `#ff` and `0xff` → 255. A number passes as it is. |

`format_number` patterns:

- `0` is a digit that is always shown; `#` a digit shown only when it is not a
  leading or a trailing zero. `0.5` with `#.##` is `.5`, with `0.00` `0.50`.
- A comma in the whole part sets the group size: the digits after the last
  comma (`#,##0` groups by 3).
- `%` in the text around the number multiplies by 100: `0.0%` gives `25.6%`
  for 0.256.
- Text before and after the number part stays as it is: `€ #,##0.00`.
- A pattern is at most 64 bytes, a separator at most 8. An empty
  `group_separator` gives no groups. A pattern without `#` or `0` gives
  `null`.

### Trigonometry (degrees)

| Type | What it gives |
|---|---|
| `sin`, `cos`, `tan`, `cot` | The function of `in` degrees. `cot 0` is `null`. |
| `asin`, `acos` | The angle in degrees; outside −1…1 `null`. |
| `atan` | The angle in degrees of the point (`x`, `in`); `x` defaults to 1, so it is the arc tangent of `in`. |
| `to_degrees`, `to_radians` | The conversion. |

The degree factors are the reference's own: `57.29577951308232 × asin(x)` and
`cos(0.017453292519943295 × x)`, so the last digit agrees with it.

### Statistics

`average`, `median`, `mode`, `std_deviation` and `variance` take the variable
inputs (`inputs`, default `in.0`, `in.1`). An input that holds a list gives its
numbers, so one wire from a `split` or a history column is enough. At most 1000
numbers count.

- `median` of an even count is the mean of the two middle numbers (the
  reference takes the upper one).
- `variance` and `std_deviation` are of the population (÷ n).
- `mode` is the value that occurs most often, compared as text; `null`, empty
  text, lists and maps do not count. A tie goes to the value that got there
  first.
- No number at all gives `null`.

### Text and codecs

| Type | Inputs | Outputs | Parameters and what it gives |
|---|---|---|---|
| `left`, `right` | `in` | `out` | `length` (default 0): the first or the last characters of `in` as text. |
| `trim` | `in` | `out` | The text without spaces at its start and end. `null` gives empty text, as the reference. |
| `base64_encode` | `in` | `out` | A text (as UTF-8) or bytes as Base64. Another value gives `null`. |
| `base64_decode` | `in` | `out`, `bytes` | Base64 (standard or URL alphabet, padding optional): `out` as text (UTF-8; a bad sequence is U+FFFD), `bytes` as bytes. No Base64: `null`. |
| `url_encode` | `in` | `out` | A URL component: every byte but `A–Z a–z 0–9 - _ . ! ~ * ' ( )` as `%XX`. |
| `url_decode` | `in` | `out` | `+` is a space, `%XX` a byte, a bad or cut `%` stays as it is (`100%` → `100%`). |
| `to_camel_case` | `in` | `out` | `Hello World-foo` → `helloWorldFoo`; `abc 2nd` → `abc2Nd`. |
| `from_camel_case` | `in` | `out` | `HelloWorld` → ` hello world` (each capital becomes a space and the small letter). |
| `hash` | `in` | `out` | `algorithm` (`sha256` default, `sha1`, `md5`): the digest of a text (as UTF-8) or of bytes in lower-case hex. |
| `json_parse` | `in` | `out`, `parse_error` | A JSON text as a value. A value that is no text passes as it is. No JSON: `out` `null`, `parse_error` true. |
| `json_stringify` | `in` | `out` | `pretty` (default false): a value as JSON text. Bytes become Base64 text. |

- Text results are at most 4 KiB, as every text block: a longer one is `null`
  with quality `bad`. JSON texts (`json_parse` in, `json_stringify` out) are
  at most 256 KiB, a parsed value at most 32 levels deep.
- `md5` and `sha1` are check sums a device or a service may ask for. Do not
  use them for a secret.

Older text blocks, changed by this set (a config without the new field gives
what it gave before):

- `substring` takes `end`: without `length`, the part ends before the
  character `end`; below 0 counts from the end (`start 1`, `end -1` on
  `[abc]` gives `abc`). `length` wins over `end`. An overrun still clamps (the
  reference gives `null`).
- `replace` takes `regexp` (default false): `from` is then a pattern. `to` is
  taken as it is: `$1` is no group.
- `case` takes the operator `regexp`: `in` as text has a match of the case.

ОБЕРЕЖНО: a pattern is at most 256 bytes and 64 KiB compiled. The engine
(the `regex` crate) has linear time and no backreferences, so a pattern from a
port cannot hang the flow. A pattern that does not compile matches nothing
and replaces nothing.

### Date and time

A date value is a number of **microseconds** since the Unix epoch, as the time
`t` of every sample, a history row and `last_run`. A date input also takes
text: RFC 3339 (`2026-10-29T13:00:00Z`, `…+02:00`), a date and time without an
offset (`2026-10-29T13:00:00`, read in `time_zone`), `yyyy-M-d`, `yyyy/M/d` and
`M/d/yyyy`, each with an optional `H:mm[:ss[.fff]]` and `am`/`pm`.

`time_zone` (default `UTC`) is an IANA name (`Europe/Kyiv`), `UTC` or an offset
`±HH:MM`. A wall time in a DST gap moves forward; a time that occurs twice
takes the earlier instant.

УВАГА: the default zone is `UTC`, not the broker host's zone. Set `time_zone`
on every date block that shows or counts wall time.

| Type | Inputs | Outputs | Parameters and what it gives |
|---|---|---|---|
| `now` | `in` | `out` | The current time on each sample of `in` (wire a `timer` for a clock). |
| `date_time` | the parameter ports | `out` | `year` (default 1970), `month`, `day` (default 1), `hour`, `minute`, `second`, `millisecond` (default 0), `time_zone`. Parts overflow as a calendar counts: month 13 is January of the next year, day 0 the last day of the month before. A part that is not whole is cut. |
| `date_format` | `in` | `out` | `format` (default `yyyy-MM-dd'T'HH:mm:ss`), `time_zone` (also `auto`: the offset written in the input text). |
| `date_parse` | `in` | `time`, `year`, `month`, `day`, `hour`, `minute`, `second`, `millisecond`, `weekday` | `time_zone`. `weekday` 1 is Monday, 7 Sunday. A text that is no date gives `null` on every output. |
| `date_math` | `in` | `out` | `op` (`after` default, `before`), `year`, `month`, `day`, `hour`, `minute`, `second`, `millisecond`, `time_zone`. |
| `date_range` | `in`, `next`, `previous` | `start`, `end`, `this_range`, `next_range`, `previous_range`, `formatted`, `duration` | `format`, `range_delimiter` (default `/`), `keep_special` (`none`, `raw`, `formatted`), `week_start` (default `monday`), `time_zone`. |

Pattern letters of `date_format` and `date_range.format`: `yyyy` (`yy` two
digits), `M`/`MM`, `MMM` (`Oct`), `MMMM` (`October`), `d`/`dd`, `D` (day of the
year), `E` (`Thu`), `EEEE` (`Thursday`), `H`/`HH`, `h`/`hh` with `a`
(`AM`/`PM`), `k`, `K`, `m`/`mm`, `s`/`ss`, `S`… (fraction digits), `Z`
(`+0200`), `xxx` (`+02:00`), `XXX` (as `xxx`, `Z` for UTC). Text in single
quotes stays as it is; `''` is a quote. A letter is always a pattern letter:
quote words (`'at'`). A pattern is at most 128 bytes. Names are English.

`date_math`:

- Years, months and days count on the calendar of `time_zone`. Jan 31 + 1
  month is the last day of February. A day over a DST change keeps the wall
  time (it lasts 23 or 25 hours). The reference adds days as 24 hours each.
- Hours, minutes, seconds and milliseconds are elapsed time.

`date_range` reads a range text:

| Text | Range |
|---|---|
| `today`, `yesterday` | the day, from 00:00 to 23:59:59.999999 |
| `thisWeek`, `lastWeek` | seven days from `week_start` |
| `thisMonth`, `lastMonth`, `thisYear`, `lastYear` | the calendar month or year |
| `current<N><unit>` | the last N units up to now (`current3days`) |
| `previous<N><unit>` | the N units before `current<N><unit>` |
| `2026`, `2026-10`, `2026-10-29` | the year, the month, the day |
| `<a>/<b>` | from `a` to `b`; an end written to the second takes the whole second |

- Units: `seconds`, `minutes`, `hours`, `days`, `weeks`, `months`, `years`;
  N is 1 … 100 000. A name may also be written in snake case (`this_week`).
- `start` and `end` are microseconds, `end` inclusive. `duration` is
  `end − start + 1`. `this_range` is `start/end` as
  `yyyy-MM-ddTHH:mm:ss` in `time_zone`.
- `next_range` and `previous_range` are the texts of the neighbours: `today`
  ↔ `yesterday`, `thisX` ↔ `lastX`, `currentN` ↔ `previousN`, the next and
  the previous year, month or day, an `a/b` range shifted by its length.
- A sample on `next` or `previous` (not one born at the start) moves the block
  to that neighbour. A new value on `in` drops the move.
- A named or a relative range is calculated again every second, so `today`
  rolls over at midnight and `current1hours` moves with the clock. A change
  goes out only when an output changed.

### Logic and events

| Type | Inputs | Outputs | Parameters and what it gives |
|---|---|---|---|
| `router` | `in`, `condition`, `in.<inputs>` (the cases) | `out.<inputs>`, `else` | `op` (as `case`, default `=`), `single_output` (default false), `inputs`. `in` goes out on `out.<name>` of the first case that `condition` matches, else on `else`. |
| `event_gate` | `reset`, `in.<inputs>` | `on_finish`, `order` | `log_order` (`none` default, `first_occurrence`, `last_occurrence`, `all`), `inputs`. An event once every input changed at least once since the last reset. |
| `catch_error` | `in.<inputs>` | `out`, `code`, `source`, `on_error` | `inputs`. Wire the `error` outputs of readers and commands into it: `out` is the message, `code` the status code, `source` the input's name, `on_error` an event for each error. |

`router`:

```json5
{ type: "router", inputs: ["high", "low"], op: ">=",
  values: { "in.high": 90, "in.low": 0 } }
// edges: ["level.out", "r.condition"], ["alarm.event", "r.in"],
//        ["r.out.high", "notify.trigger"], ["r.out.low", "log.trigger"]
```

- A case value is the input `in.<name>`; give it a constant in `values`.
- `single_output: true` sets the output routed before back to `null` when the
  route changes. Without it each output keeps its last value.
- `router` routes on any sample on `in`, `condition` or a case.

`event_gate`:

- A sample born at the start does not count, and the gate fires once. A
  sample on `reset` (not one born at the start) opens it again.
- `order` lists the input names joined with commas; with `all` it keeps the
  last 1000 changes. The reference numbers the inputs; WYRM names them.

`catch_error` has no error groups: the reference routes an error to every
catcher of the same group without a wire. A wire keeps the cycle check, `watch`
and `preview` true to the graph (ADR 0044 §7).

### Readers: history and node

| Type | Inputs | Outputs | Parameters |
|---|---|---|---|
| `load_history` | `trigger`, `in.key`, `in.interval_ms`, `in.auto_run`, `in.enabled`, `in.time_range`, `in.rollup`, `in.window`, `in.limit`, `in.time_zone` | `out`, `ok`, `error`, `running`, `last_run` | `key`, `key_scope`, `interval_ms`, `auto_run` (default true), `enabled`, `time_range` (default `today`), `rollup` (default `none`), `window`, `limit` (default 10 000), `time_zone` (default `UTC`) |
| `get_node` | `trigger`, `in.key`, `in.interval_ms`, `in.auto_run`, `in.enabled` | `out`, `actions`, `ok`, `error`, `running`, `last_run` | `key`, `key_scope`, `interval_ms`, `auto_run` (default true), `enabled` |

`load_history` reads the historian (`~val?history=`, `docs/history.md`):

- `time_range` is a range text as `date_range` reads it: `today`,
  `lastWeek`, `current24hours`, `2026-10`, `<a>/<b>`. Wire
  `date_range.this_range` into `in.time_range` for a fixed or a named range a
  user moves with `next` and `previous`.
- For a sliding range (`current24hours`), write the text itself into
  `time_range` and set `interval_ms`. `this_range` of a sliding range changes
  every second: wired into `in.time_range`, it asks the historian once a
  second. A change while a read runs reads again after it.
- `window` (`5m`, `1h`, `1d`, `1w`; empty: none) and `rollup` (`avg`, `min`,
  `max`, `sum`, `count`, `first`, `last`, `delta`, `and`, `or`) give one row
  per window.
- `out` is a table (ADR 0044 §2) with the columns `t` (microseconds), `v` and
  `q` (the quality code; `null` for a rollup row).
- `limit` is 1 … 10 000. An answer that reached the limit may have more rows:
  the `ok` event then carries `truncated: true` and `rows`. A table larger than
  512 KiB is an `error` with `resource_exhausted`.
- A changed query field (`in.time_range`, …) reads again when `auto_run` is
  true. A history read has 30 s to answer.

`get_node` reads a node's `~meta`:

- `out` is its summary: `{name, display, type, unit, enum, writable, is,
  has_children}`.
- `actions` is a table `{name, display, group, level, params}`; `params` is a
  list of `{name, type, default, required, display, description, unit,
  enum}`. It gives an action's default arguments (the reference's Get Default
  Parameters).

Both read inside a scope as `load_value` does: the deployer, every watcher and
every previewer must read the key and all of `key_scope`.

Every reader (`load_value`, `list_children`, `load_history`, `get_node`) also
runs on `dataflows/<id>/~act/trigger {node}` (the editor's `Run` button). The
caller then needs read on the reader's key and all of its scope (for
`list_children` also on the children), not a command's level.

УВАГА: a run that a trigger starts flows on along the edges. When a `set` or an
`invoke` is downstream of the triggered node (directly, through other blocks
or inside a custom block), the caller also needs that block's level on its
target: `max(maxperm, write)`. A reader with no command downstream needs read
alone. The same holds for a command block whose answer runs another command.

### Tables

A table is a value (ADR 0044 §2):

```json
{"columns": ["name", "kw"], "rows": [{"name": "pump", "kw": 3}, {"name": "fan", "kw": 7}]}
```

- `columns` gives the order; each row is a map. A cell a row lacks is `null`.
- Every table input also takes a list of maps, as `list_children` and
  `load_history` give them; its columns are the keys in the order they first
  appear. Rows given as lists (`{"columns": [...], "rows": [[...]]}`) are taken
  by position.
- There is no index column (the reference has `row` in column 0): a row's
  index is its place, from 0.
- Bounds: 10 000 rows, 128 columns, a column name of 256 bytes, 512 KiB of
  cells, a cell 29 levels deep. A larger result is `null` with quality `bad`.
- The parsers check their bounds while they read, not after:
  `table_from_csv` refuses (`parse_error` true) a text past 512 KiB, a row of
  more than 128 fields (a header too: it is not cut) and a field past 64 KiB;
  a row map of more than 128 keys is no table; `table_from_json` and
  `json_parse` read at most 256 KiB and 32 levels; a list of names
  (`columns`, `ignore_columns`) counts its first 512 items. Equal or empty
  header names get `_2`, `_3`, … in one pass.
- A table block takes a table on `in` and gives a new one: the mutators
  (`table_add_row`, `table_edit_rows`, `table_remove_rows`) are transforms, not
  writes into a stored table. Keep a table across samples in a
  `table_recorder`, or write it to broker storage with `set`.

Per-row scripts (`table_filter`, `table_remove_rows`, `table_edit_rows`,
`table_map_columns`) are rhai, with two variables: `row` (the row as a map:
`row.kw`, `row["kw rate"]`) and `index` (from 0). A column name is not a
variable: names come from the data, and the compiler checks a script when the
flow is deployed. `state` is a map that lives for one table. A missing cell is
`()`: write `row.kw != () && row.kw > 5`. All the scripts of one table have
100 ms; past that the block gives `null` and the reason on `error`.

| Type | Inputs | Outputs | Parameters and what it gives |
|---|---|---|---|
| `table` | `in` | `out` | `value`: a table, sent at start as a variable. |
| `table_recorder` | `reset`, `in.<inputs>` | `out` | `enabled`, `buffer_size` (default 1024, at most 10 000), `time_window_s`, `ignore_null`, `inputs`. A row `{t, <input>…}` for each sample on an input (`t`: the sample's time, µs); a sample on `reset` clears it (a table on `reset` replaces the rows). |
| `table_from_csv` | `in` | `out`, `parse_error` | `with_header` (default true), `delimiter` (default `,`). Cells are texts. |
| `table_to_csv` | `in` | `out` | `with_header`, `delimiter`. |
| `table_from_json` | `in` | `out`, `parse_error` | `selector` (`data.items`, `a[0].b`). A list of objects (nested keys as `a/b`), one object, or `{columns, rows}`. |
| `table_to_json` | `in` | `out` | `pretty`. The rows as JSON objects. |
| `table_map_columns` | `in` | `out`, `error` | `retain_columns`, `mapping`: `[{name, from}]`; `from` is a column, `= expr` (a value), `+ expr` (a number), `& expr` (a bool). |
| `table_sort` | `in` | `out` | `column`, `method` (`number`, `string`, `natural`), `order`. No value sorts last either way; equal keys keep their order. |
| `table_filter` | `in` | `out`, `error` | `expr`: the rows for which it is true. |
| `table_remove_rows` | `in` | `out`, `error` | `expr`: the rows for which it is false. |
| `table_edit_rows` | `in` | `out`, `error` | `expr`, `cells` (`{<column>: <value>}`): each matching row gets the cells. |
| `table_group_by` | `in` | `out` | `column`, `include_blank`, `nested` (a column `rows` with each group's table), `aggregates`. |
| `table_join` | `in`, `right` | `out` | `column`, `right_column` (default: `column`), `join` (`left`, `inner`, `right`, `full`, `exclude`, `union`). |
| `table_page` | `in`, `next`, `previous`, `first`, `last` | `out`, `current_page`, `total_pages` | `page_size` (default 10; below 0: all), `page` (from 0). |
| `table_rollup` | `in` | `out` | `time_column` (default `t`), `interval` (default `1h`), `round_time` (default true), `method`, `aggregates`, `week_start`, `time_zone`. |
| `table_aggregate` | `in` | `out` | `column`, `method`. One value. |
| `table_select_rows` | `in` | `out` | `indexes`: `0,2,5`, a list or a number. |
| `table_select_columns` | `in` | `out` | `columns`: `name,zone` or a list. |
| `table_columns` | `in` | `out` | A table `{name, type}`; `type` is `number`, `string`, `bool`, `map`, `list`, `bytes`, `mixed` or `null`. |
| `table_row_cells` | `in` | `out`, `count` | `row`: that row as a map; `count`: the rows. Wire `get` for one cell. |
| `table_add_row` | `in` | `out` | `row`: a map appended (a `make_object` gives one; a new key adds its column). |
| `table_transpose` | `in` | `out` | `header_column`, `include_headers`, `header_prefix` (default `c`), `ignore_columns`. |
| `table_from_map` | `in` | `out` | A map as a one-row table; a table passes. |

`aggregates` (of `table_group_by` and `table_rollup`) is a list
`[{column, method, as}]`; `as` names the result (default: the column). The
methods: `first`, `last`, `count` (cells with a value), `sum`, `average`,
`min`, `max`, `median` (sorted; the reference takes the middle row as it
stands), `mode`, `std_deviation`, `variance`, `concat`, `concat_unique` (texts
joined with commas, at most 4 KiB).

`table_join`, as the reference: one to one, the first row of the other table
with the key counts; keys compare as text (`1` matches `"1"`). `left` keeps
every row of `in` and adds the new columns of `right`; `inner` only the rows
with a match; `right` every row of `right` (its cells win); `full` the rows of
`in` with a key, once each, then the rows of `right` none of them has;
`exclude` the rows of `in` that `right` lacks; `union` all rows of both. A
table with no key column passes `in` (for `right`: `right`).

`table_rollup`:

- `interval` is a number and a unit: `s`, `m` (minutes), `h`, `d`, `w`, `M`
  (months), `y`. The reference's names (`fiveMinutes`, `oneHour`, `day`, …)
  are taken too.
- `round_time: true` starts the buckets on round times in `time_zone`
  (`15m`: :00, :15, …; `1d`: midnight; `1w`: `week_start`); `false` starts
  them at the first row's time, as the reference's default.
- A bucket without rows gives no row. The time cell is the bucket's start in
  microseconds.
- Without `aggregates`, every other column is reduced by `method`.

```json5
// the hourly maximum of a day of history
{ h: { type: "load_history", key: "downstream/plc/t1", time_range: "yesterday" },
  r: { type: "table_rollup", interval: "1h",
       aggregates: [{ column: "v", method: "max", as: "t_max" }] } }
// edges: ["h.out", "r.in"]
```

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
| `invoke` | `in`, `trigger`, `in.interval_ms`, `in.auto_run`, `in.enabled`, `arg.<name>` | `out`, `result`, `sent`, `ok`, `error`, `running`, `last_run` | `path`, `action`, `args`, `on`, `allow_bad`, `interval_ms` (default 0), `auto_run` (default false), `enabled` (default true), `run_on_start` (default false) |
| `set` | `in`, `trigger`, `in.interval_ms`, `in.auto_run`, `in.enabled` | `sent`, `ok`, `error`, `running`, `last_run` | `path`, `on`, `deadband`, `allow_bad`, `interval_ms` (default 0), `auto_run` (default true), `enabled` (default true), `run_on_start` (default false) |

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
| `run_on_start: true` | one run, 250 ms after each start of the flow | one write of the value `in` got by then |

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

There is one action block. A block that runs on a trigger, a block that runs
at deploy and a periodic block are the same `invoke` with other fields; there
is no block type per behaviour. The older `on` of `invoke` still works for
`in`: `change` is what `trigger` does, and `rising` or `falling` is a
`rising_edge` or `falling_edge` block wired into `trigger`.

ОБЕРЕЖНО: `run_on_start: true` is the one exception to the rule above. The
block then runs once at every start of the flow: each deploy, each hot swap,
each reload and each broker restart. Set it only on a command that is safe to
repeat.

The `trigger` action is the block's button in the editor. It needs level
`write` on the flow, and the caller needs `write` on the block's own target
(the flow's `maxperm` when that is higher).
It works on a deployed flow that runs. In a preview a command block shows what
it would send (`sinks`), fires `sent`, and never `ok` or `error`.

## Custom blocks

A custom block is a sub-flow that a flow uses as one block (spec 06 0.2.24,
ADR 0040 §3). The definition carries it in `blocks`; a node of type
`block:<name>` is an instance.

```json
{
  "blocks": {
    "mean": {
      "inputs": [
        {"name": "a", "to": "sum.in.0"},
        {"name": "b", "to": "sum.in.1"},
        {"name": "k", "to": "div.in.1", "default": 2}
      ],
      "outputs": [{"name": "out", "from": "div.out"}],
      "nodes": {"sum": {"type": "add"}, "div": {"type": "divide"}},
      "edges": [["sum.out", "div.in.0"]]
    }
  },
  "nodes": {"m1": {"type": "block:mean", "values": {"k": 4}}},
  "edges": [["x.out", "m1.a"], ["y.out", "m1.b"], ["m1.out", "r.in"]]
}
```

- The fields of an instance are the block's inputs and outputs, in their
  order. A parameter is an input with a `default`.
- `values` gives an input its constant for this instance. A wire replaces it.
- The compiler replaces the instance by the inner nodes `m1/sum` and `m1/div`.
  `watch`, `ports` and `preview` show them under these ids; `nodes: ["m1"]`
  asks for all of them.
- A block may hold other blocks, at most 4 deep and at most 64 instances in
  one block. A block may not contain itself. The 1000 nodes of a flow count
  every inner node and every instance; a flow has at most 4000 edges with its
  blocks expanded.
- A constant goes only to an inner input that keeps one: a parameter's port,
  an operand of a logic block, an argument of `invoke`, `in` of a variable.
- A block with a `publish` inside can be used once in a flow.

The library keeps blocks for every flow of the site:

1. Store a block: `dataflows/~act/put_block {name, def}` (level `config`).
2. Read it: `get_block {name}` gives `{name, version, def, requires}`.
3. Copy `def` and every block of `requires` into `blocks` of the flow.
4. Deploy the flow.

`list_blocks` lists them; `remove_block {name}` removes one. A flow holds its
own copy: a change in the library reaches a flow when the block is copied and
the flow is deployed again.

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

**Pins (owner decision 2026-11-09, as DGLux `!ps`).** The rows below are a
type's defaults: a block draws its *pinned* fields, and the inspector lists
every field with a pin to put it on the block or take it off. A field with a
wire is always a row. The user's choices travel in the definition's `layout`
(`flow-editor.md` §12).

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
10. A key field takes a wire inside a scope (ADR 0040 §1; the catalog's
    `params[].scope`). When `Point` (`subscribe`, `liveliness`,
    `load_value`) or `Node` (`list_children`) gets a wire and the block has
    no scope, the editor asks for it on the field: `This block may read
    keys under`, with the key's parent and all below it proposed
    (`downstream/modbus/line1/**`), the site's sections as chips, and the
    engine's rule checked as it is typed (inside `downstream`, `dataflows`
    or `storage` of this site). Save writes `key_scope`; Cancel takes the
    wire away. The scope then shows as the row `Scope`; unbinding keeps it.
    The deployer's and the watcher's rights on the scope (for
    `list_children` also on its children, `<scope>/*`) are checked by the
    engine, not by the editor.
11. A block with behaviours (`invoke`, `set`, `load_value`, `list_children`:
    a `trigger` input and the event outputs) lists its fields in groups in
    the inspector: Target, Arguments, Behaviour, Events, State. On the
    block only what the user set or wired shows beyond the defaults in the
    table. An unbound `Trigger` of a command block is a `Run` button: the
    engine's `dataflows/<id>/~act/trigger {node}` on the DEPLOYED flow, off
    with the reason while the draft differs from the deployed version. An
    event output reads when it last fired, `error` with its code and
    message. In a preview the block's trigger row reads `would send …`.
12. An action dragged from the Tree tab becomes an `invoke` with `path`,
    `action` and one argument per parameter of the action (its default,
    else nothing yet); required arguments are rows of the block. The
    action's own parameter types come from the node's `~meta` and choose
    each argument's editor.
13. A custom block (ADR 0040 §3) is made from a selection (`Create custom
    block…`: a name, and a name per port; an input may get a default), kept
    in the definition's `blocks`, and drawn as one block per instance. Its
    inside opens on the canvas (`Open inside`, `Edit custom block`) with an
    `Inputs` block and an `Outputs` block: a wire from `Inputs.<a>` to an
    inner field is the `to` of input `a`, a wire from an inner output into
    `Outputs.<x>` the `from` of output `x`. The My blocks tab lists the
    flow's blocks and the site's library (`list_blocks`); a library block
    placed is copied into the flow with the blocks it uses (`get_block`).
14. On a broker without ADR 0040 (no `scope` in the catalog, no type with
    `trigger: true`, `list_blocks` not answered) the editor draws the
    older shape and says why a thing is off: a key field takes no wire
    (`This broker cannot bind …`), `Run` is off, My blocks and the
    custom-block items of the menu are off.

| Type | Fields on the block, in order | Field ← engine | Inspector only | Editors | Engine gap against the DGLux block |
|---|---|---|---|---|---|
| `number`, `string`, `bool` | Value ⇄ | Value = `in` → `value` → `out` | — | number box; text (`string`: multi-line in DGLux); toggle | none: DGLux has the one field `value` |
| `const` | Value → | Value = `value` → `out` | — | JSON or text | no input (sent once at start) |
| `subscribe` | Point ⇄ · Scope (once a wire feeds Point, or a scope is written; a pencil opens its prompt) · `<point>` → · Error → (once a wire feeds Point) | `in.key` → `key`; `key_scope`; the point's value on `out`; `error` | — | Point: a text, or a wire; Scope: the prompt on the field, or a text field that says why a scope is refused | none (spec 06 0.2.22) |
| `liveliness` | Node ⇄ · Scope · `<node>` → · Error → (as `subscribe`) | `in.key` → `key`; `key_scope`; `out`; `error` | — | as `subscribe` | none (spec 06 0.2.22) |
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
| `set` | `<point>` ⇄ (a behaviour that is set shows too) | `in` → its echo `in` | Target: Point (`path`) · Behaviour: Trigger (unbound: `Run`) · Auto run · Every · Enabled · Run on start · Write on · Deadband · Allow bad quality · Events: Sent, Ok, Error · State: Running, Last run | Run button (`~act/trigger`); toggles; Every: a number and its unit; Run on start asks first with the catalog's warning | none (spec 06 0.2.23) |
| `invoke` | header `<node> · <action>` · `<required argument>` ⇄ … · Trigger ⇄ · Ok → · Error → (a behaviour that is set shows too) | `arg.<name>` ⇄ (constant in `args`); `trigger`; `ok`, `error` | Target: Node (`path`), Action · Arguments: the action's other parameters · Behaviour: Run when (`in`), Auto run, Every, Enabled, Run on start, Run on, Allow bad quality · Events: Sent · State: Output (`out`), Result, Running, Last run | an argument as its action types it (choices, toggle, number, text); Run button; Every: a number and its unit; Run on start asks first | none (spec 06 0.2.23); the target is static (ADR 0040 §1a) |
| `wasm` | Artifact → · `<input>` ⇄ … · `<output>` → … | ports named by `inputs`/`outputs` | Config, Fuel, Memory (MB) | — | — |
| `add`, `subtract`, `multiply`, `divide`, `max`, `min` | Input 1 ⇄ · Input 2 ⇄ · … · Output → (− / +, at least 2) | `in.0`, `in.1`, …; `out` | — | operands typed (`values`) | none (spec 06 0.2.19: an operand holds a typed value) |
| `abs`, `not`, `length` | Input ⇄ · Output → | `in`; `out` | — | `in` typed (`values`) | none |
| `round` | Input ⇄ · Precision ⇄ · Min precision ⇄ · Output → · Text → | `in`; `in.precision` → `precision`, `in.min_precision` → `min_precision`; `out`, `text` | — | `in` typed (`values`) | none (spec 06 0.2.21: `text` is DGLux's text result) |
| `modulo` | Input ⇄ · Modulo ⇄ · Quotient → · Remainder → | `in`; `in.modulo` → `modulo` | — | — | — |
| `if` | Operation ⇄ · Input 1 ⇄ · Input 2 ⇄ · … · Then ⇄ · Else ⇄ · Output → | `in.op` → `op`; `in.<n>`; `in.then` → `then`, `in.else` → `else` | — | Operation dropdown (`=`, `!=`, `and`, `or`, `>`, `<`, `>=`, `<=`, `contains`, `starts_with`, `ends_with`); operands typed | none (spec 06 0.2.20, 0.2.21) |
| `case` | Input ⇄ · Operation ⇄ · Case 1 ⇄ · Then 1 ⇄ · … · Else ⇄ · Output → (− / + by a pair, at least one) | `in`; `in.op` → `op`; pairs `in.<n>` by position; `in.else` → `else`; `out` | — | Operation dropdown; cases and thens typed (`values`) | none: `regexp` is bounded (spec 06 0.2.28) |
| `hub` | Input 1 ⇄ · Input 2 ⇄ · … · Ignore null ⇄ · Output → · Index → · On change → | `in.<n>`; `in.ignore_null` → `ignore_null`; outputs | — | Ignore null toggle; operands typed | none |
| `stopwatch` | Reset ⇄ · Enabled ⇄ · Interval (s) ⇄ · Step ⇄ · Modulo ⇄ · Loop ⇄ · Reset value ⇄ · Output → · On loop → | `reset`; `in.<p>` → `p` | — | Enabled, Loop toggles | — |
| `trace` | Tracing ⇄ · Message ⇄ · Input 1 ⇄ · Input 2 ⇄ · … | `in.tracing` → `tracing`, `in.msg` → `msg`; `in.<n>` | — | Tracing toggle; operands typed | none |
| `concat` | Input 1 ⇄ · Input 2 ⇄ · … · Strict ⇄ · Output → | `in.<n>`; `in.strict` → `strict`; `out` | — | Strict toggle; inputs typed (`values`) | no separator (none in DGLux either) |
| `load_value` | Point ⇄ · Scope · Trigger ⇄ · Error → · Output → | `in.key` → `key`; `key_scope`; `trigger`; `error`, `out` | Behaviour: Auto run, Every, Enabled · Events: Ok · State: Running, Last run | as `subscribe` for Point and Scope; Run button (`~act/trigger`, the caller reads the key and the scope) | none (spec 06 0.2.28) |
| `list_children` | Node ⇄ · Scope · Trigger ⇄ · Error → · Output → | `in.path` → `path`; `path_scope`; `trigger`; `error`, `out` | as `load_value` | as `load_value` | — |
| `substring`, `replace`, `split`, `join`, `get` | Input ⇄ · `<parameter>` ⇄ … · Output → | `in`; `in.<p>` → `<p>`; `out` | — | a parameter typed as the catalog says | — |
| `make_object`, `make_array`, `select` | `<input>` ⇄ … (`select`: Index ⇄ first) · Output → (− / +) | `in.<name>` (named inputs keep their names); `in.index` → `index`; `out` | Inputs (list) | inputs typed (`values`) | — |
| `stats` | Input ⇄ · Min → · Max → · Average → · Sum → · Count → | `in`; `min`, `max`, `avg`, `sum`, `count` | — | — | — |
| `changed`, `rising_edge`, `falling_edge` | Input ⇄ · On change → / On edge → | `in`; `on_change` / `on_edge` (an event: the row reads when it fired) | — | — | — |
| `counter`, `toggle` | Input ⇄ · Reset ⇄ · Step ⇄ · Initial ⇄ · Output → | `in`, `reset`; `in.<p>` → `<p>`; `out` | — | Initial: a number / a toggle | — |
| `sample_and_hold` | Input ⇄ · Trigger ⇄ · Output → | `in`, `trigger`; `out` | — | — | — |
| `debounce`, `throttle` | Input ⇄ · Quiet time (ms) ⇄ / Period (ms) ⇄ · Output → | `in`; `in.ms` → `ms`; `out` | — | — | — |
| `block:<name>` (an instance of a custom block) | header `MY` · `<input>` ⇄ … · `<output>` → … · `Open inside` | an input: the inner input its `to[0]` names (its constant in `values`, else the block's `default`); an output: the inner output `from`; live values from the rows `<instance>/<inner>` | — | an input typed as any value (`2` is a number, `AHU-` a text) | an instance has no row of its own in `watch` (ADR 0040, deferred) |
| `constant` | Name ⇄ · Value → | `in.name` → `name`; `out` | — | Name dropdown | none |
| `factorial`, `parse_number`, `sin`, `cos`, `tan`, `cot`, `asin`, `acos`, `to_degrees`, `to_radians` | Input ⇄ · Output → | `in`; `out` | — | `in` typed (`values`) | none |
| `log`, `power`, `root`, `atan` | Input ⇄ · Base / Exponent / Degree / X ⇄ · Output → | `in`; `in.<p>` → `<p>`; `out` | — | — | none |
| `bound` | Input ⇄ · Min ⇄ · Max ⇄ · Input out of range → · Output → | `in`; `in.min`, `in.max`; outputs | — | — | none |
| `round_up`, `round_down` | Input ⇄ · Precision ⇄ · Output → · Text → | `in`; `in.precision`; `out`, `text` | — | — | none (`text` is the reference's text result) |
| `format_number` | Input ⇄ · Format ⇄ · Decimal separator ⇄ · Group separator ⇄ · Output → | `in`; `in.<p>`; `out` | — | — | none |
| `average`, `median`, `mode`, `std_deviation`, `variance` | Input 1 ⇄ · Input 2 ⇄ · … · Output → (− / +) | `in.<n>`; `out` | — | operands typed (`values`) | `median` of an even count averages (ADR 0044 §5) |
| `left`, `right` | Input ⇄ · Length ⇄ · Output → | `in`; `in.length`; `out` | — | — | none |
| `trim`, `base64_encode`, `url_encode`, `url_decode`, `to_camel_case`, `from_camel_case` | Input ⇄ · Output → | `in`; `out` | — | `in` typed (`values`) | none |
| `base64_decode` | Input ⇄ · Output → · Bytes → | `in`; `out`, `bytes` | — | — | none |
| `hash` | Input ⇄ · Algorithm ⇄ · Output → | `in`; `in.algorithm`; `out` | — | Algorithm dropdown | none |
| `json_parse` | Input ⇄ · Output → · Parse error → | `in`; `out`, `parse_error` | — | — | none |
| `json_stringify` | Input ⇄ · Pretty ⇄ · Output → | `in`; `in.pretty`; `out` | — | Pretty toggle | none |
| `now` | Input ⇄ · Output → | `in`; `out` | — | — | new (the reference has no clock block) |
| `date_time` | Year ⇄ · Month ⇄ · Day ⇄ · Hour ⇄ · Minute ⇄ · Second ⇄ · Millisecond ⇄ · Time zone ⇄ · Output → | `in.<p>` → `<p>`; `out` | — | — | `millisecond` is used (the reference reads it under a wrong name) |
| `date_format` | Input ⇄ · Format ⇄ · Time zone ⇄ · Output → | `in`; `in.format`, `in.time_zone`; `out` | — | — | microseconds, not milliseconds (ADR 0044 §3) |
| `date_parse` | Input ⇄ · Time zone ⇄ · Time → · Year → · … · Weekday → | `in`; `in.time_zone`; the parts | — | — | none |
| `date_math` | Input ⇄ · Operation ⇄ · Year ⇄ · … · Millisecond ⇄ · Time zone ⇄ · Output → | `in`; `in.<p>`; `out` | — | Operation dropdown | days on the calendar (ADR 0044 §5) |
| `date_range` | Input ⇄ · Next ⇄ · Previous ⇄ · Format ⇄ · Delimiter ⇄ · Keep special ⇄ · Week start ⇄ · Time zone ⇄ · Start → · End → · This range → · Next range → · Previous range → · Formatted → · Duration → | `in`, `next`, `previous`; `in.<p>`; outputs | — | Keep special, Week start dropdowns | none: `week_start`, `time_zone` and `previousN` work (the port's gaps) |
| `router` | Input ⇄ · Condition ⇄ · Operation ⇄ · Case 1 ⇄ · … · Single output ⇄ · Output 1 → · … · Else → (− / + adds a case and its output) | `in`, `condition`; `in.op`, `in.single_output`; `in.<case>` with `out.<case>`; `else` | Inputs (list) | Operation dropdown; cases typed (`values`) | none (the reference's `event` is `in`) |
| `event_gate` | Reset ⇄ · Log order ⇄ · Input 1 ⇄ · … · On finish → · Order → | `reset`; `in.log_order`; `in.<n>`; outputs | — | Log order dropdown | `order` lists names, not numbers |
| `catch_error` | Input 1 ⇄ · … · Output → · Code → · Source → · On error → | `in.<n>`; outputs | — | — | wired, no `errorGroup` (ADR 0044 §7) |
| `load_history` | Point ⇄ · Scope · Time range ⇄ · Rollup ⇄ · Window ⇄ · Trigger ⇄ · Error → · Output → | `in.key` → `key`; `in.<p>`; `trigger`; `error`, `out` | Behaviour: Auto run, Every, Enabled · Limit, Time zone · Events: Ok · State: Running, Last run | as `load_value`; Rollup dropdown; Run button | the reference's `header`, `delta`, `unifyTimezone` are left out (`t` is µs; a `table_map_columns` renames) |
| `get_node` | Node ⇄ · Scope · Trigger ⇄ · Error → · Output → · Actions → | `in.key` → `key`; `trigger`; `error`, `out`, `actions` | as `load_value` | as `load_value` | none |
| `table` | Value ⇄ | Value = `in` → `value` → `out` | — | a table editor (JSON today) | none |
| `table_recorder` | Reset ⇄ · Input 1 ⇄ · … · Enabled ⇄ · Buffer size ⇄ · Time window (s) ⇄ · Ignore null ⇄ · Output → | `reset`; `in.<n>`; `in.<p>`; `out` | Inputs (list) | — | rows `{t, <name>}`; no index column |
| `table_from_csv`, `table_to_csv`, `table_from_json`, `table_to_json` | Input ⇄ · `<parameter>` ⇄ … · Output → (· Parse error →) | `in`; `in.<p>`; outputs | — | — | `table_from_json` keeps a nested list as one cell (the reference drops it without filters) |
| `table_map_columns` | Input ⇄ · Retain columns ⇄ · Output → · Error → | `in`; `in.retain_columns`; outputs | Mapping (list of name/from) | Mapping: rows of name and from | expressions are rhai over `row`, `index` |
| `table_sort`, `table_aggregate`, `table_select_rows`, `table_select_columns`, `table_row_cells`, `table_add_row`, `table_transpose`, `table_columns`, `table_from_map` | Input ⇄ · `<parameter>` ⇄ … · Output → | `in`; `in.<p>`; outputs | — | Method / Order dropdowns | none |
| `table_filter`, `table_remove_rows`, `table_edit_rows` | Input ⇄ · (Cells ⇄) · Output → · Error → | `in`; (`in.cells`); outputs | Expression | Expression: multi-line | rhai over `row`, `index` |
| `table_group_by`, `table_rollup` | Input ⇄ · `<parameter>` ⇄ … · Output → | `in`; `in.<p>`; `out` | Aggregates (list of column/method/as) | Aggregates: rows of column, method, as | one type for the reference's Rollup and Advanced Rollup |
| `table_join` | Input ⇄ · Right ⇄ · Column ⇄ · Right column ⇄ · Join ⇄ · Output → | `in`, `right`; `in.<p>`; `out` | — | Join dropdown | `renameColumns` left out (`table_map_columns` renames) |
| `table_page` | Input ⇄ · Next ⇄ · Previous ⇄ · First ⇄ · Last ⇄ · Page size ⇄ · Page ⇄ · Output → · Current page → · Total pages → | `in`, triggers; `in.<p>`; outputs | — | — | none |

The editor takes the ports from the catalog (a parameter's `port`), so a
port the engine adds shows without an editor change. Parameters the engine
has no input for show no left port, and a wire dragged onto them is refused
with `<field> takes no input: type its value`. Today these are `expression`
`expr`, `trigger`, `quality`; `filter` `expr`; `latch` its
parameter `reset`; `window` `kind`, `fn`, `max_samples`; `alarm` `on_bad`;
a scope (`key_scope`, `path_scope`); the command targets (`set.path`,
`invoke.path`, `invoke.action`, ADR 0040 §1a) and `run_on_start`
(`crates/wyrm-flow/src/catalog.rs`).
