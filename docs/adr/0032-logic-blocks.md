# ADR 0032 — Logic blocks in the flow engine

**Status:** accepted · 2026-11-01 (owner: a server-side list of blocks like the editor prototype's; decided under ADR 0029).

## Context
The owner keeps a Dart prototype of a block editor with its own engine (not in this repository). Its blocks are variables, arithmetic, `if`, `hub`, `stopwatch`, `trace` and text blocks. The flow engine (`wyrm-flow`, spec 06) had `expression`, `scale`, `window` and other node types, but not these. The owner asked for the same list on the server.

The prototype binds an input to an output by a path stored on the input. The flow engine sends samples on edges between ports. The blocks follow the engine's model.

## Decision
1. **One module, `wyrm_flow::blocks`.** Types: `number`, `string`, `bool`, `add`, `subtract`, `multiply`, `divide`, `max`, `min`, `abs`, `round`, `modulo`, `not`, `if`, `hub`, `stopwatch`, `trace`, `concat`, `length`. `nodes::ports` and `nodes::build` ask it first. The catalog lists them for the editor.
2. **A parameter is config and, where it makes sense, a port.** The value comes from the config or its default; a sample on `in.<parameter>` replaces it. Variable inputs are the config list `inputs` (default `0`, `1`, at most 64), ports `in.<name>`; a name may not be a parameter's.
3. **Names are snake_case**, as every other node type's (`input_min`, `reset_value`, `ignore_null`, `on_change`, `on_loop`). The prototype's camelCase names are not taken.
4. **Change-only outputs, by value and quality.** A good-to-bad change of the same value goes out (honest quality). Events always go out, as `{event, id}`.
5. **Operators do not calculate at start.** Only the variables send at start. A deploy, a hot swap or a restart never fires a command by itself. The prototype calculates every block when it is attached; the engine does not.
6. **Numbers as in the prototype where it matters:** integers stay integers while they fit, `divide` gives a float, non-finite results are `null`, `modulo`'s quotient goes toward 0 and its remainder is never negative, `round` to 0 places gives an integer.
7. **`scale` keeps its meaning.** `k × in + b` stays; the range form (`input_min` … `output_max`, output `input_out_of_range`) applies only once a range parameter is set or arrives. An existing `scale` with no config stays the identity.
8. **`stopwatch`** runs on a 50 ms clock (the runtime reads `tick_every` once), counts at most every 0.05 s, and keeps its count across a hot swap.
9. **`trace` logs at `trace` only**: its lines hold values.
10. **The editor draws fixed ports and named ports together** (`if`: `in.then`, `in.else`, then `in.0`, …); `dyn_inputs` adds to `inputs` instead of replacing it.
11. **Texts a block makes are at most 4 KiB** (`concat`, `string`), as the expression engine's strings; a longer one is `null` (`concat`: quality `bad`). A `concat` in a loop through a `delay` would otherwise grow without end (automated review of `e89b1d4`).

*If wrong:* a flow that expects an operator's value right after deploy must start from a variable or a `const`; a block that should send every sample (not only changes) needs a `filter` or an `expression` in front of its sink.

## Found on the way
`publish`, `set` and `invoke` started one task per sample, so two samples close together could be written in the other order: a published value could end on the older one, and a `set` could leave a device at the older value (`true` then `false` arriving as `false` then `true`). Each of these nodes now has one writer task: `publish` and `invoke` keep the order (a queue of 256; more are dropped and logged at `debug`), `set` writes the newest value (older ones not yet written are skipped). The test `logic_blocks_in_a_deployed_flow` failed 5 times in 6 before this.

## Not done
The prototype's own editor protocol (binding paths, its save format) is not taken: flows stay spec 06 definitions. Further block types come as the owner names them.
