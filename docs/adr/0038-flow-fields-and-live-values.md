# ADR 0038 — Flow fields and live values

**Status:** proposed · 2026-11-08 (owner: the flow editor must show live values and treat every input as "a value or a binding", as DGLux does; screen spec `studio/docs/design/specs/flow-editor.md`; decided under ADR 0029).

## Context
The flow editor spec (`flow-editor.md` §3) draws a block as **fields**: every parameter and every input is one row with a value, a left port (input) and a right port (output); outputs have only a right port. Values are live. DGLux (`dglux_flutter`) works the same way: one slot per field holds a typed value, an optional binding, and feeds other blocks.

The engine today (research 2026-11-08):
- publishes only the flow's `~val` and the `publish` nodes' values; nothing per port (`runtime.rs` `run_node` only routes outputs);
- lets a logic block's parameter be config and port `in.<p>` (ADR 0032 §2), last sample wins, but `node_types` does not say which parameter has a port, gives `default` only for choices and as a string, and gives no port types;
- has no output for a parameter or an input, so a field cannot feed another block;
- has no way to watch a running flow or to run a draft.

ADR 0019 chose Deploy-only: no live `~set` of a field.

## Decision

### 1. Every field is also an output
- For each parameter `p` of a node: an output port **`p`** carrying the parameter's **effective** value (config or default, replaced by the last sample on `in.<p>` where that port exists). It sends once when the node starts and then on every change.
- For each input port `x` that is not a parameter's port (`in`, `in.0`, `in.1`, …): an output port **`x`** that repeats every sample the node receives on `x`, before the node handles it.
- Names: the output is named exactly like the parameter or the input (`scale1.input_min`, `if1.in.0`). Edges already split at the first dot (`def.rs` `endpoint`), so `a.in.0` is node `a`, port `in.0`.
- A clash with an existing output of the node (a parameter named like an output) keeps the existing output; that field has no echo output and the catalog says so (`echo: false`). An input's echo comes before a parameter's: `latch` has the input `reset` and the parameter `reset`, so the parameter has no echo (`echo: false`). This is the only static clash today.
- Cost: an echo output that no edge reads is never built. The compiler knows the edges; the runtime does not copy a sample for an unwired echo.

### 2. The catalog says what a field is (additive)
`node_types` keeps `inputs`, `outputs`, `dyn_inputs`, `dyn_outputs` and `params` as they are, and adds:
- per parameter: `port` (`"in.<p>"` when the parameter has an input port, absent otherwise), `default` as a typed value for every parameter that has one (a number stays a number; choices keep their string), `echo` (`true` unless §1's clash rule removes it);
- per node type: `port_types: {<port>: <type name>}` for inputs and outputs (`number`, `bool`, `string`, `any`, … as `PortType::name`), and `echo_inputs: true` when inputs repeat as outputs.

### 3. `dataflows/<id>/~act/watch` — live values of a deployed flow
- Level `read` on `dataflows/<id>`, `stream: true`, `timeout_ms: 30000`.
- Args: `nodes` (optional list of node ids; absent = all), `max_hz` (optional, default 4, at most 20, per node).
- **Rights:** the caller's `ptok` `auth` (spec 04, as DQL queries) must cover reading every source (`subscribe`, `liveliness`) and every command target (the node of each `invoke`/`set`) of the flow; otherwise `permission_denied` naming the first key the caller cannot read. The values of a flow are derived from its sources, an `invoke` node's output carries its target's answer and a `set` node's input is what it writes there (security review 2026-11-08).
- **Rows:**
  1. first: `{t, snapshot: true, nodes: {<node>: {in: {<port>: [v, q]}, out: {<port>: [v, q]}, params: {<p>: v}}}}` — the last value of every port and the effective value of every parameter;
  2. then: the same shape with `snapshot: false` and only what changed since the last row, at most `max_hz` rows per node per second (the latest value wins inside a period);
  3. a heartbeat `{t, nodes: {}}` when nothing changed for 10 s (the gateway's idle wait per reply is `timeout_ms` + 5 s);
  4. the stream ends after 30 min (`ttl`), on a redeploy (`{t, redeployed: <version>}` as its last row), on remove, or when the caller goes; the editor opens it again.
- **Cost:** ~~the runtime records the last sample of a port only while at least one watch of that flow is open~~ (changed 2026-11-08, spec 06 0.2.18, see §6 "From the start"): the runtime keeps the last sample of every port from the start. Watches per flow ≤ 8, per site ≤ 64 (`busy` beyond).
- Values are never logged above `trace`.

### 4. `dataflows/<id>/~act/ports` — one snapshot
Level `read`, same rights check, returns row 1 of §3. For tools (`wyrm-agent`, MCP) that do not keep a stream.

### 5. `dataflows/~act/preview` — live values of an undeployed draft (2026-11-08, spec 06 0.2.16)
The owner added a `concat` block to a draft in the Studio editor and saw no values: the engine runs only deployed flows. The editor must show live values on every field of the draft while it is edited, with no risk to devices.
- On the `dataflows` root: level `read`, `stream: true`, `timeout_ms: 30000`. Args: `def` (a spec 06 definition, the shape `deploy` takes), `nodes` (optional list of node ids), `max_hz` (optional, default 4, at most 20).
- **Compile:** the definition compiles as for deploy and validate (every step of spec 06, the sources' sections and the `wasm` artifacts included); an error is `invalid_parameter` with the compiler's message. `version`, `enabled` and `permissions.maxperm` are not checked against anything: nothing is deployed, and no `proofs` are needed, because nothing is written.
- **Rights:** as `watch` (§3): the caller's `auth` covers read on every source (`subscribe`, `liveliness`) and every command target (the node of each `invoke`/`set`); otherwise `permission_denied`. A `read` user may preview a draft with a `set` it may not write: it sees what the set would write, which it may read anyway.
- **Sandbox:** a real runtime instance of the draft that nothing persists: no store, no `~def`, no node states (it starts with none and drops them at the end), no node in the tree. Its place is the preview registry, never the engine's flows, so a draft with the id of a deployed flow touches neither that flow nor its watches. It reads through a session client **without tokens**.
- **Sinks cannot write by construction:** the node builder has a preview mode (`nodes::Mode::Preview`) in which `set`, `invoke` and `publish` are capture nodes. A capture node holds no client, no writer task and no `ctx`, and never reads its `Io`. It applies the deployed node's own rule (`allow_bad`, `on`, `deadband`, `$in` in `args`; one function for both modes) and reports the result. An `invoke` capture sends nothing on `out` (there is no answer).
- **Rows:** exactly `watch`'s (§3: snapshot row, change rows at most `max_hz` per node, heartbeat `{t, nodes: {}}` after 10 s), and any row may carry `sinks: [{node, op, key, value}]`:
  - `op` is `set`, `invoke` or `publish`;
  - `key` is the full key it would write: `wy/<site>/<path>/~set`, `wy/<site>/<path>/~act/<action>`, `wy/<site>/dataflows/<def.id>/nodes/<node>`;
  - `value` is the value it would write, or for `invoke` the arguments map after `$in`.
  The snapshot holds each sink's latest; a change row holds the sinks that acted since the previous row, the latest per node (a row of sinks alone is a change row with `nodes: {}` and `snapshot: false`). `nodes` filters sinks too.
- **Recorded from the start:** the probe is held before the first node runs, so every port's last sample is kept from the start. The first row waits (at most 500 ms) until every node task runs and a round of asks passes in which no node records anything (each task answers an ask only once its inbox is empty). So the snapshot shows the variables' start values and what they fed.
- **Ends:** after 10 min (`ttl`; the editor opens it again with its latest draft), when a newer preview of the same subject takes its place, on a node panic (the stream ends with `internal_error`; a preview never restarts) and when the engine stops (the engine waits up to 2 s for each preview to stop its runtime). Timers, `stopwatch`, `delay` and `window` run as in a deployed flow.
- **Caps:** at most 2 previews per subject (`origin`, else `sub`; a third ends that subject's oldest) and 16 per site (`busy` beyond). The caps use the watch registry with the subject in the flow's place.
- **Cost (measured 2026-11-08, Apple M4 Max, release, `tests/preview_cost.rs`):** live heap about 8 KB per node (10 nodes: 105 KB, 100: 0.85 MB, 1000: 8.2 MB), with the inbox growing on demand rather than reserved; a node task is one tokio task. The first row came after 25 ms (10 nodes) to 94 ms (1000 nodes in one chain, the start value passing every hop). Idle, a preview of blocks wakes only for its heartbeat; a source costs what it costs in a deployed flow, plus one lock and one value copy per port sample for the recorder. Bounds: **at most 1000 nodes per flow** (new compiler limit, spec 06 step 8; it applies to deploy and validate too), so one preview is at most about 8 MB, and 16 previews at most about 130 MB.

### 5a. Not now
- **Live `~set` of a field** stays out (ADR 0019): a field changes by Deploy.
- **Done 2026-11-08 (spec 06 0.2.17):** the older node types take the parameters the editor binds on `in.<p>`, as ADR 0032 §2 (the config or default first, the last good sample wins): `scale` `k`, `b`; `alarm` `high`, `low`, `hysteresis`, `delay_s`, `return_delay_s`; `delay` `ms`; `window` `size_s`; `deadband` `abs`, `pct`; `timer` `period_ms`. Each is a `number` port, listed in the catalog's `inputs` and as the parameter's `port`. A sample that is not a finite number, or is outside the parameter's bounds (`period_ms` ≥ 10, `size_s` > 0, `ms` ≥ 0, `delay_s`/`return_delay_s` ≥ 0), is ignored. The config rules stay (`high` or `low`, `abs` or `pct`, `period_ms`, `size_s`, `ms` required): the config gives the start value. A parameter that changes a node's clock (`period_ms`, `ms`, `size_s`, the alarm's delays) takes effect at once: the runtime starts the new clock one period after the change. A `delay` sample already waiting keeps its time. Not ported: `expression`, `filter` (their parameters are scripts), and choices (`kind`, `fn`, `on_bad`, `max_samples`).

### 6. Implementation notes (2026-11-08, §1–§4 built; spec 06 0.2.15)
- **Echo types:** an input's echo has the input's port type; a parameter's echo is `number`, `bool` or `map` as the parameter's catalog type, every other type (`string`, `dynamic`, `array`) `any`. Every parameter has an echo, `inputs`/`outputs`/`args` included, and every node type, `wasm` included (there a declared output keeps its name over an echo at compile time).
- **`port_types`** lists the fixed inputs and outputs, the dynamic ports of their `default` names (`in.0`, `in.1`) and every echo output; dynamic ports of other names are `any`.
- **A parameter's echo sends at start**, so an edge from it to `invoke`/`set` fires a command at deploy (the one exception to ADR 0032's rule; `docs/flow-blocks.md` warns).
- **The caller's going is not seen.** The SDK keeps a stream's reply channel open until the action ends, and a reply to a gone requester does not fail, so a dropped watch lives until its ttl. At a cap, a new watch of the same subject (`origin`, else `sub`) ends that subject's oldest watch (on the flow; at the site cap, anywhere on the site); another subject's watch is `busy`. An editor that reopens on every start stays within the caps.
- **`permission_denied`** travels without its text (the SDK never sends one with that status); the engine's error names the first key, but the requester gets the status only.
- **Snapshots** hold what was recorded: a port with no sample since the flow started is absent from `in`/`out` (all three maps are always in row 1).
- **From the start (2026-11-08, spec 06 0.2.18; owner review of the Studio editor):** on the demo, `ahu2_ctl` has variables feeding `concat1`; a variable sends once at deploy, so a watch opened later showed `in`/`out` empty forever. The runtime now keeps the last sample of every input and output of a deployed flow from the start, watched or not; `watch`'s snapshot and `ports` show them. Design: one record per node, each behind its own lock, made when the flow starts (a node task locks only its own record and never waits for another node; a watch locks each record in turn); one slot per port, made on the port's first sample and overwritten in place afterwards; one change counter per flow (an atomic). A watch is woken only while one is open. Measured (Apple M4 Max, release, `watch::tests::record_cost`): one record of an input and an output costs about 20 ns for numbers and 54 ns for texts (a text is copied; a number or a bool allocates nothing after the port's first sample); a node call records twice (its input before it runs, its outputs after), so about 25–65 ns per node call, against one atomic load before. Memory: about 100 bytes per port that had a sample, plus a text's or a map's own bytes, once per port and not per sample. The 5 s `KEEP` time is gone.
- **Ends:** ttl, remove and an engine stop end the stream without a row; a redeploy ends it with `{t, redeployed: <version>}`. `nodes` absent or empty = every node; an unknown id is `invalid_parameter`; `max_hz` outside (0, 20] is `invalid_parameter`.
- Stop/start, reload and a panic restart keep the watches (one recorder per deployed version).
- **Preview (§5, built 2026-11-08):** a preview's caller going is not seen either, as for `watch`: a dropped preview runs until its ttl, and the per-subject cap (a third preview ends the subject's oldest) bounds what one editor leaves behind.
- **Ask barrier:** a node task answers a request for its parameters only once its inbox is empty, after the iteration that emptied it. A watch's snapshot and a preview's first row so hold what start queued (a variable's value); a busy node answers within the 200 ms wait or not at all.
- **Source tasks end with their node:** `subscribe` and `liveliness` keep their I/O tasks and abort them when the node drops (a stop, a hot swap, the end of a preview). Before, every redeploy left one Zenoh subscriber per source running.

### 5b. Ports for the remaining block parameters (2026-11-08, spec 06 0.2.20)
So every field can be bound: `concat` `in.strict`, `if` `in.op`, `hub` `in.ignore_null`, `trace` `in.tracing`, `in.msg`, with the blocks' rule (config first, the last sample wins). `if.op` takes only an operator it knows; another text is ignored and the last good one stays. Every logic-block parameter now has a port, apart from a variable's `value` (its input `in` does that) and `inputs` (it names the ports).

### 7. Operands hold a typed value (2026-11-08, spec 06 0.2.19; owner review of the Studio editor, DGLux semantics)
A block field is one entity: a typed value that a binding can replace. A parameter already is (config, then its port). An operand input (`in`, `in.0`, `in.1`, … of `add`, `concat`, `if`, …) had no constant.
- **Config shape:** one node key `values: {<port>: <value>}`, e.g. `{type: "concat", values: {"in.0": "AHU-", "in.1": 2}}`. Chosen over flat `"in.0": 5` keys: a node's config keys stay its parameters (spec 06 schema, `only()` checks), port names with a dot never become config keys, and one key is easy to check and to drop. A key must be an **operand input** of the block: `in` (where the block has it) or `in.<name>` of its `inputs`; never a parameter's port (that parameter's config is its constant), never `stopwatch.reset` (an event), and not the variables (`number`, `string`, `bool`: their `value` is the constant). Anything else is a compile error `nodes.<id>: values.<port>: not an operand input …`; the value can be any value.
- **Meaning:** the constant is the input's value until a sample on that input replaces it (a binding wins). Removing the edge and deploying again falls back to the constant. Quality and time come only from inputs that had a sample. `watch`/`ports`/`preview` show each constant as the input's value from the start (`Node::seeds`).
- **Safety (ADR 0032's rule kept):** a constant **seeds** its input and calculates nothing. A block calculates on its first real sample (on any input or parameter port), as before. So a deploy, a hot swap or a restart never fires a `set` or `invoke` because of a constant. A block of constants only stays without output: a constant expression is a variable's job. Refused alternative: evaluate at start and make command sinks drop start-time samples; it needs a start mark carried through every block and changes what a variable feeding a `set` does today.
- **Scope:** the logic blocks (`crate::blocks`). Not `expression` and the older types (their single `in` is the sample they act on).
- **Catalog:** per type `values: true` when its operand inputs (fixed `inputs` and the `dyn_inputs` ports that are not a parameter's `port`) take a constant.

### 8. Block gaps against DGLux (2026-11-08, spec 06 0.2.21; semantics from `dglux_flutter/lib/runtime/blocks_core.dart`)
- `if.op` gains `!=` (the first input equals none of the others, compared as `=`), `contains`, `starts_with`, `ends_with` (the first input as text with any of the others; a `null` other never matches; a `null` first is empty text). Names are snake_case (ADR 0032 §3): DGLux's `startsWith`/`endsWith` are refused at compile.
- `round.min_precision` (port `in.min_precision`, no default = `precision`) and a new output **`text`**: DGLux's round gives text when it has places; WYRM keeps `out` a number (its port type, its edges) and adds `text` with `precision` places, trailing zeros trimmed down to `min_precision` places.
- A **`case` block**: input `in`; `op` (`=`, `!=`, `>`, `<`, `>=`, `<=`, `contains`, `starts_with`, `ends_with`, default `=`) and `else` (default `null`), both with ports; the variable inputs `inputs` are pairs (case value, then value), usually given as constants in `values` (§7). It sends the then of the first pair whose case matches `in`, else `else`; it calculates on any sample, as every block. An empty case text matches nothing in the text operators (as DGLux). DGLux's `regexp` is left out: a pattern from a port can take any time to match, and the flow crate has no bounded regex engine.

*If wrong:* a field that should not feed other blocks gets an output anyway (harmless while unwired); a watch that misses a sample between two periods shows the latest value only, which is what an editor needs.

## Studio
The flow editor builds fields from the catalog (§2; until the broker has it, from a matching `in.<p>`), draws a right port on every field (§1), and fills values from `watch` (§3) for a deployed flow and from `preview` (§5) for a draft, re-opening either when it ends (a preview also on every change of the draft). The old lookup of `dataflows/<flow>/nodes/<block id>` for live values is removed: that key exists only for `publish` nodes.
