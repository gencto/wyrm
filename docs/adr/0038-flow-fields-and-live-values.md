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
- **Cost:** the runtime records the last sample of a port only while at least one watch of that flow is open; with none open, `run_node` does nothing more than today. Watches per flow ≤ 8, per site ≤ 64 (`busy` beyond).
- Values are never logged above `trace`.

### 4. `dataflows/<id>/~act/ports` — one snapshot
Level `read`, same rights check, returns row 1 of §3. For tools (`wyrm-agent`, MCP) that do not keep a stream.

### 5. Not now
- **Live preview of an undeployed draft** (`dataflows/~act/preview {def, ttl_s}`) needs sinks that cannot write by construction (no `set`/`invoke` built at all), reads with the caller's rights, caps on concurrent previews, a TTL and no persistence. It comes in its own pull request with its own section here.
- **Live `~set` of a field** stays out (ADR 0019): a field changes by Deploy.
- Older node types (`alarm`, `window`, `deadband`, `delay`, `expression`, `scale` `k`/`b`) get `in.<p>` ports later, one by one, as the editor needs them.

### 6. Implementation notes (2026-11-08, §1–§4 built; spec 06 0.2.15)
- **Echo types:** an input's echo has the input's port type; a parameter's echo is `number`, `bool` or `map` as the parameter's catalog type, every other type (`string`, `dynamic`, `array`) `any`. Every parameter has an echo, `inputs`/`outputs`/`args` included, and every node type, `wasm` included (there a declared output keeps its name over an echo at compile time).
- **`port_types`** lists the fixed inputs and outputs, the dynamic ports of their `default` names (`in.0`, `in.1`) and every echo output; dynamic ports of other names are `any`.
- **A parameter's echo sends at start**, so an edge from it to `invoke`/`set` fires a command at deploy (the one exception to ADR 0032's rule; `docs/flow-blocks.md` warns).
- **The caller's going is not seen.** The SDK keeps a stream's reply channel open until the action ends, and a reply to a gone requester does not fail, so a dropped watch lives until its ttl. At a cap, a new watch of the same subject (`origin`, else `sub`) ends that subject's oldest watch (on the flow; at the site cap, anywhere on the site); another subject's watch is `busy`. An editor that reopens on every start stays within the caps.
- **`permission_denied`** travels without its text (the SDK never sends one with that status); the engine's error names the first key, but the requester gets the status only.
- **Snapshots** hold only what was recorded: a port with no sample since recording began is absent from `in`/`out` (all three maps are always in row 1). Recorded values stay 5 s after the last watch closes, so a watch opened again at once keeps them. `ports` holds the recorder for its own call only, so its port values come from an open watch.
- **Ends:** ttl, remove and an engine stop end the stream without a row; a redeploy ends it with `{t, redeployed: <version>}`. `nodes` absent or empty = every node; an unknown id is `invalid_parameter`; `max_hz` outside (0, 20] is `invalid_parameter`.
- Stop/start, reload and a panic restart keep the watches (one recorder per deployed version).

*If wrong:* a field that should not feed other blocks gets an output anyway (harmless while unwired); a watch that misses a sample between two periods shows the latest value only, which is what an editor needs.

## Studio
The flow editor builds fields from the catalog (§2; until the broker has it, from a matching `in.<p>`), draws a right port on every field (§1), and fills values from `watch` (§3), re-opening it when it ends. The old lookup of `dataflows/<flow>/nodes/<block id>` for live values is removed: that key exists only for `publish` nodes.
