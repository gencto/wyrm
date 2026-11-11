# ADR 0040 — Flow behaviours: keys from a port, the action block, custom blocks

**Status:** proposed · 2026-11-09 (owner requirements of 2026-11-09 for the next round of the Studio dataflow editor: bind a block's output into the path of another block; the action block with behaviour fields; custom blocks; the blocks still missing; decided under ADR 0029). Goal: a service block takes `path` as a field that a binding can drive, and has a trigger, an interval, auto run and the events sent, ok and error. Names are WYRM's (ADR 0032 §3).

## Context
ADR 0038 made every parameter and input a field with a value, a port and an output. Three things stayed fixed in the config:
- the key a source reads (`subscribe.key`) and the target of a command (`set.path`, `invoke.path`);
- when a command runs (only a sample on `in`);
- the set of block types (no block made of blocks).

The key is the hard one. The engine reads through the broker's own session, which no ACL sees. Today a deploy checks every source against the deployer's rights (`reads_sources`, security review FLOW-1) and every command target against a proof token (ADR 0008). Both checks are static: they read the config. A key that arrives on a port at run time passes neither.

## Decision

### 1. A key from a port stays inside a scope approved at deploy (spec 06 0.2.22)
- **Field.** `subscribe.key` and `liveliness.key` get the input port `in.key`. The config `key` stays the start value and may be absent.
- **Scope.** A node whose `in.key` is wired must carry `key_scope`: a key expression, relative to `wy/<site>/` or absolute, for example `downstream/modbus/line1/**`. No scope and a wired port is a compile error (`nodes.<id>.key_scope: required when in.key is wired`). There is no default scope.
- **Where a scope may lie.** Inside this site's `downstream`, `dataflows` or `storage`, as a static source (spec 06 step 9). The section is a literal prefix of the scope, so no wildcard of it can reach `sys`, `pub`, `upstream` or another site. Checked by deploy, validate, preview and the start of a stored flow.
- **Deploy.** The deployer's `auth` (spec 04) must give `read` on **all** of the scope, as it must on a static key. `reads_key` walks the grants in the responder's order: a grant below `read` that touches the scope refuses it; a read grant that covers all of it accepts it; a read grant on a part leaves the rest to the grants after it. So a deny grant on one point inside the scope refuses the deploy, and every key inside an accepted scope is a key the deployer reads.
- **`watch`, `ports`, `preview`.** The same check for their caller (`reads_flow`): a flow's values come from whatever the scope lets it read.
- **Run time.** `Scope::admit` takes a value from the port only when it is: a text; not empty; at most 512 bytes; one concrete node key (every segment `[A-Za-z0-9_.-]+`: no `*`, `**`, `$*`, no `~meta`/`~val` suffix, no empty segment, no selector); inside this site's `downstream`, `dataflows` or `storage`; and included by the scope. A static `key` of the config may still be a pattern; a key from a port never is.
- **A new key.** The old read ends first. `out` sends `null` with quality `uncertain`, and stays so until the new key's first sample. The node's effective `key` (its echo output and `params.key` in `watch`) is the key as written. A sample of a read that has ended is dropped (each read has a number).
- **A refused value.** Nothing is read. `out` is `null`/`uncertain`, the effective `key` is `null`, and the new output `error` carries the reason as a text. `error` goes back to `null` with the next admitted key. The refused value is never logged.
- **`null` on the port** reads nothing and is no error.
- **Rate limit.** Two changes are at least 100 ms apart. A value that comes earlier waits; the latest one wins.
- **After deploy.** A flow keeps running when its deployer loses rights (ADR 0008). The same holds for a scope.

**The security argument.** The engine's read power is the broker's. The deployer's rights bound it at deploy, key by key. A scope is a set of keys named in the definition, so the same bound holds: (a) the set is in the definition that the deployer signs for and that `~def` and the history show; (b) the deployer reads every key of the set, deny grants included; (c) the runtime reads one key at a time and only a member of the set; (d) a member is a node key, so the read cannot become a wildcard read, a `~meta` read or a query with a selector; (e) whoever watches the flow reads the set too. A flow with a scope reads no more than a flow with one static `subscribe` per key of the scope would, and that flow can be deployed today.

**Refused alternatives.**
- *A scope by default (the static key's parent).* A wired port would widen what the node reads without a word in the definition.
- *Check the deployer's rights at run time for each key.* The engine has no token of the deployer after the deploy, and ADR 0008 lets a flow outlive its deployer's rights.
- *Wildcards from a port.* One sample could then read the whole scope at once; a pattern is a decision for the config, where the deploy check sees it.

### 1a. Command targets stay static in this round
`set.path`, `invoke.path` and `invoke.action` get no port. Reasons:
- A command target is approved by a **proof**: a token of the deployer for the exact key `…/~set` or `…/~act/<a>`, checked by the engine's verifier, and the flow's own tokens grant exactly these keys (ADR 0008). A scope would need a proof for a pattern. A token for a pattern does not show a deny grant inside it, so the engine could not tell whether the deployer writes every key of the scope. Spec 04 would have to say what a pattern proof means, and the gateway would have to mint one.
- A wrong read shows a value. A wrong write moves a device.
- The use case of the owner (a text block builds a path, the path drives a `subscribe`) needs reads only.

What a flow can change at run time on a command is its **arguments** (§2) and the value it writes. `publish.node` stays static too: it is a node of the tree, declared at deploy.

*If wrong:* a scope that is too wide lets a flow read more points than its author meant, but never more than the deployer reads. A dynamic command target can be added later as a scope with pattern proofs without a change to this section.

### 2. The action block: `invoke` with fields, behaviours and events (spec 06 0.2.23)
A node action dropped from the tree becomes an `invoke` block. The type keeps its name and its old behaviour; it gains argument fields, behaviour fields and events.

**Arguments are fields.** `args` stays one map. Each key is an argument: its value is the argument's constant, and the port `arg.<name>` replaces it with the last sample (the field rule of ADR 0038 §7: a typed value that a binding can replace). An argument without a constant is `null`. An argument is also an output `arg.<name>` (ADR 0038 §1). At most 64 arguments; a name is 1 to 128 bytes and does not start with `__`. The prefix `arg.` keeps arguments apart from the block's own ports, so an argument name never clashes with a port and is never changed to fit. `"$in"` as a constant still stands for the last value on `in`. The catalog says `dyn_inputs: {param: "args", prefix: "arg.", default: [], keys: true}`: `keys` means the parameter is a map and its keys name the ports.

**Behaviour fields** (config, and a port each):
| Field | Port | Default | Meaning |
|---|---|---|---|
| `interval_ms` | `in.interval_ms` | 0 | Above 0: a run every period. 0 is off; else 100 … 86 400 000. A value from the port outside these is ignored. |
| `auto_run` | `in.auto_run` | `invoke`: false · `set`: true | `invoke`: a sample on `arg.<name>` that changes the argument runs the action. `set`: a value on `in` is written (today's behaviour). |
| `enabled` | `in.enabled` | true | False: nothing runs the block, the `trigger` action included. |

**One block, not one per behaviour (owner decision 2026-11-09).** "The trigger block and the deploy-run block are in essence one block, only their behaviour differs." There is no `trigger`, `button`, `run_on_deploy` or periodic block type. `invoke` is the one action block and `set` follows the same model; the fields above and below set what runs it.

**`run_on_start`** (config, bool, default false, no port: a value from a port would come after the start). True: the block runs exactly once each time the flow starts (a deploy, a hot swap, a reload, a broker restart, a restart after a node panic), 250 ms after the node started, so the start values of bound arguments and of `in` are in. This is **the one sanctioned exception** to ADR 0032 §5 / ADR 0038 §7, and the owner's explicit choice per block; the default keeps the rule. Details: a disabled block makes no start run, and none later when it is enabled; a `set` writes the value `in` got by then (nothing when there is none), and not twice when `auto_run` already wrote it; the answers of the start run carry the start mark (below), so they run no other block through a `trigger`. The catalog's description of the field starts with `WARNING:`. In a preview the start run is a `sinks` row and never a write.

**The older `on` of `invoke`** stays as it is, for `in` only, so deployed definitions keep working unchanged. How it maps onto the fields: `on: any` on `in` is "every sample runs it"; `on: change` is what `trigger` does with a value; `on: rising` / `falling` is a `rising_edge` / `falling_edge` block (§4) into `trigger`. New flows wire `trigger`; `in` and `on` are kept, not extended.

**`trigger`** is an input without a config value. An event (`{event, id}`) runs the block. Any other value runs it when it differs from the last sample on `trigger`; the first real sample runs it. `null` runs nothing; a sample of bad quality runs nothing unless `allow_bad`. An unbound `trigger` is a button: see the action below.

**`in`** keeps its meaning: `invoke` runs on every sample that passes `on`; `set` takes the value to write.

**Outputs.**
| Output | Type | When |
|---|---|---|
| `sent` | event | The request leaves the engine. |
| `ok` | event | The target answered without an error. |
| `error` | event `{event, id, code, message}` | The target, the transport or the node's queue refused. `code` is the status code (spec 04), `message` its text. |
| `result` | any | `invoke` only: the last result. |
| `running` | bool | True from the first run handed to the writer until the last one answered. |
| `last_run` | number | The time of the last `sent`, µs since the epoch. |
| `out` | any | `invoke` only, kept: the result with quality `good`, or the error text with quality `bad`. |
One writer task per node keeps the order. `invoke` holds at most 256 calls; one more is refused with `error` `{code: busy}`. `set` writes the newest value. A period of `interval_ms` is skipped while the run before it has not answered.

**`set`** gets the same fields where they make sense: `trigger` (write the held value now, `on`/`deadband` aside), `interval_ms` (write it again every period), `auto_run` (default true; false: `in` only holds the value), `enabled`, and the outputs `sent`, `ok`, `error`, `running`, `last_run`.

**The start rule.** ADR 0032 §5 says a deploy never runs a command by itself. The new behaviours keep it by a mark on a sample, `born at the start`:
1. what a node sends because the flow started: a variable's and a `const`'s start value, a parameter echo's start value, a clock's tick at the start (`timer` sends 1 at once), the first sample of a read (`subscribe`, `liveliness`, also after a new key: the value that was already there);
2. everything a node sends while it handles a sample with the mark. The runtime carries the mark on, not the blocks: `variable → add → trigger` is marked, and so is the answer of a command that a marked sample ran.

A sample with the mark on `trigger` only gives the port its value. A sample with the mark on `arg.<name>` only fills the argument. `interval_ms` counts from the start of the node (and from a change of the period, and from `enabled` going true): the first run is one full period later. So a deploy, a hot swap, a reload and a restart after a crash run no command through `trigger`, `auto_run` or `interval_ms`. Only `run_on_start: true` does, by the owner's choice for that block. Tests: `a_deploy_never_runs_a_command_through_the_new_behaviours` and `tests/commands.rs`.

`in` is not part of the rule: a variable wired to `set.in` or `invoke.in` still writes at deploy, as ADR 0038 §6 warns. Changing that would change deployed flows. A flow that must not act at deploy uses `trigger`.

*Amended 2026-11-11 (spec 06 0.2.30):* a second mark, **made of constants** (`Msg::constant`, always with `start`), is set where a pure block with no wired input calculates at start and on `now`'s start value, and the runtime carries it on in the same way. A sample with it runs no command on any port, `in` included: it only gives the field its value. Deployed flows do not change: before 0.2.30 such blocks sent nothing at start. *Cost:* a block fed at start by both a pure block (made of constants) and a read or a variable (not) calculates twice, in the order the samples come. If the read's sample comes first, a `set` after it writes a value without the constant, then holds the full one without writing; the next real sample writes the right value. Before 0.2.30 the constant never came, so the value written at start was always without it. Tests: `pure_blocks_calculate_at_start_and_run_no_command`, `a_real_sample_through_a_constant_chain_writes`, `operand_constants_never_fire_a_command_at_deploy` (also the control: a variable on `in` still writes).

This is the alternative ADR 0038 §7 refused ("a start mark carried through every block"), in a narrower form: one bool on a sample, set at five places and carried by the runtime, and it changes no existing port's behaviour. *Cost:* a point that has no value when the flow starts gives its first value with the mark, so a `trigger` bound to it misses that one sample.

**`dataflows/<id>/~act/trigger {node}`** runs one block once.
- Level `write` on `dataflows/<id>`. The caller's `auth` (spec 04) must also give `max(maxperm, write)` on the block's own target (`…/~act/<action>` or `…/~set`), by the same grant walk as §1. This is the level the deploy asks of the deployer's proof (`proves_targets`): the flow's token for the target carries up to `maxperm`, so a caller with less would run through the flow what it may not run itself (security review 2026-11-09). The compiler caps `maxperm` at `write` today (spec 06 step 7), so the level is `write`; the gate follows `maxperm` so it holds if that cap ever moves. The engine cannot see the target action's own declared level without a read of its `~meta`; the target checks the flow's token against that level itself, and that token never carries more than `maxperm`. The flow's token only says that the deployer could; a button is pressed by a person, and that person needs the right. No `auth`: `permission_denied`.
- `node` is an `invoke` or `set` of the flow (the catalog marks these types `trigger: true`); another node is `invalid_parameter`.
- Only a deployed, running flow: a stopped flow or a flow in error is `not_supported` ("the flow is not running"). A preview has no such action.
- The run goes into the node's inbox on an internal port, in order with its samples. It runs with the block's current arguments, whether `trigger` is wired or not. A disabled block ignores it.
- The responder SDK audits the call as every action, with the caller as its subject; the target audits the command it gets with the subject `flow:<id>`, as every flow command.

**Preview.** `set` and `invoke` in a preview are the same nodes without a client or a writer (`Sink::Capture`): they decide as a deployed node does, record what they would send in the row's `sinks`, fire `sent` and set `last_run`. They never fire `ok` or `error`, never set `result`, `out` or `running`: there is no answer, and a made-up `ok` would show a success that did not happen.

**Found on the way.** Two command blocks with one target could not be deployed: `proves_targets` checked the target's proof once per block, and a proof token is taken once (`jti`, spec 04 0.2.11). It now checks one proof per target key.

### 3. Custom blocks: a sub-flow as one block (spec 06 0.2.24)
The owner selects blocks in the editor and says "create custom block", later "edit custom block" (`docs/studio.md` §10 item 8). The engine's part is small: the compiler replaces an instance by the block's nodes. The runtime, `watch`, `preview`, the rights checks and the proofs never see a custom block.

**In the definition.**
```
"blocks": { "<name>": {
  "description": tstr?,
  "inputs":  [ { "name": tstr, "to": "<inner>.<port>" | [ "<inner>.<port>", … ], "default": any?, "description": tstr? } ],
  "outputs": [ { "name": tstr, "from": "<inner>.<port>", "description": tstr? } ],
  "nodes": { <inner_id>: { "type": tstr, …config } },
  "edges": [ [ "<inner>.<port>", "<inner>.<port>" ] ],
  "layout": { <inner_id>: [ x, y ] }?
} }
"nodes": { "<id>": { "type": "block:<name>", "values": { "<input>": <value> }? } }
```
- `inputs` and `outputs` are lists: an editor draws the fields in their order. A name is `[A-Za-z0-9_]+`, unique among inputs and outputs together. At most 64 of each; an input feeds 1 to 16 inner inputs.
- **Parameters are inputs with a `default`.** The brief asked for `params`; a separate list would be a second kind of field. A field of an instance is an input: a constant (`values.<input>` of the instance, else the input's `default`) that a wire can replace, as every field since ADR 0038 §7.
- An instance takes `values` only. Its ports are the block's inputs and outputs: `["x.out", "m1.a"]`, `["m1.out", "y.in"]`. An input is also an output of its name (`["m1.a", "z.in"]`): the echo of the first inner input it feeds.
- At most 64 blocks in a definition, names `[A-Za-z0-9_]+`.

**Inlining** (`def::parse`).
- An inner node gets the id `<instance>/<inner>`; in a nested block `<instance>/<inner instance>/<inner>`. A `/` is the engine's: an author's id stays `[A-Za-z0-9_]+`.
- An edge into an instance input becomes one edge per inner input it feeds; an edge from an instance output starts at the inner output.
- A constant goes where the inner input keeps one: a parameter's port → that parameter's config; an operand of a logic block → its `values`; `arg.<name>` of an `invoke` → `args`; `in` of a variable → `value`; an input of an inner instance → that instance's `values`. An inner input that keeps no constant (`filter.in`, `set.in`) refuses one: `nodes.<id>.values.<input>: <inner>.<port> takes no constant`. So a constant never sends a sample, and ADR 0038 §7 holds inside a block.
- An inner node's config hash is computed after the constants. Two instances with the same values have the same inner hashes; a redeploy keeps the state of every inner node that did not change.
- A block may hold instances of other blocks of the same definition. Depth at most 4; a block that holds itself is refused. The limit of 1000 nodes counts the expanded nodes.
- **The expansion is charged while it is made (security review 2026-11-09).** `validate` and `preview` compile a draft at level `read`, so a block that multiplies must cost bounded work. Limits: every plain node **and every instance**, at every depth, counts against the 1000 nodes as it is added; the edges, as written and as rewired, count against **4000 edges** per flow (new, validation step 8), and the walk from an instance input to its inner inputs stops when that room is used up; one block holds at most **64 instances** of other blocks, at most 1000 nodes and 4000 edges; a definition holds at most 64 blocks; depth at most 4. **A block that contains itself**, directly or through others, is refused on the definitions before anything is expanded (`blocks.a: a custom block may not contain itself (a → b → a)`). Tests (`expansion_bombs_are_refused_quickly`): 64⁴ nested instances, hollow blocks of instances only, and an input that fans out to 16 at each of 4 levels are each refused in under 50 ms.
- **Compile cost at the limits** (measured 2026-11-09, Apple M4 Max, `the_largest_definition_compiles_in_bounded_time`: 909 nodes in blocks 4 deep, 85 instances, 1816 edges): 2.6 ms in a release build (expansion 1.6 ms, checks 1.0 ms), 12 ms in a debug build. So the compile stays under the engine's state lock, as before. On the way: the compiler made a script engine for every node, with or without a script, which was 55 ms of 56 ms for this definition; it now makes one only for `expression` and `filter`. A definition of 1000 `expression` nodes still pays for 1000 engines (about 60 µs each), as it did before this ADR.
- The compiler's messages name the place as written: `blocks.mean.edges[0] in m1: …`, `edges[2]: m1 (mean) has no input x`.
- A `publish` inside a block has the same `node` name in every instance, so such a block can be used once per flow (validation step 7a).
- `~def` and the history keep the definition as it was sent, with `blocks`.

**The inside in `watch`, `ports` and `preview`.** Rows carry the inner nodes under their ids: `nodes: {"m1/sum": {in, out, params}}`. The argument `nodes` takes an instance id and then means all its inner nodes (`nodes: ["m1"]`). An instance has no row of its own: its field `a` is the inner input `to[0]` of the block's input `a`, and its output is the inner output `from`. The editor has the block's definition and reads both there. The `trigger` action takes an inner id (`node: "m1/call"`).

**The library** (`dataflows`, in the flow store, replicated with it; store SCHEMA 4).
| Action | Level | Args | Answer |
|---|---|---|---|
| `put_block` | config | `name`, `def` (one block, the shape above) | `{name, version}`; each put is the next version |
| `get_block` | read | `name` | `{name, version, def, requires: {<name>: def}}`: with every library block it uses |
| `list_blocks` | read | — | `[{name, version, description?, inputs: [names], outputs: [names]}]` |
| `remove_block` | config | `name` | — (`not_found` when absent) |
- `put_block` checks the block as a deploy would: alone in a probe flow with the library blocks it uses (`invalid_parameter` with the compiler's message; a used block the library does not hold is refused). At most 256 blocks, 256 KiB each.
- **A flow copies, it does not link.** The editor takes a block with `get_block` and writes it (and its `requires`) into the definition's `blocks`. The engine never reads the library when it compiles. Reasons: a deploy stays self-contained (the definition, its history and a rollback hold all of it; a standby and a downstream site need no library); the gateway and the tools compute command targets and proofs from the definition alone (`command_targets`); and a change in the library cannot change a running flow without a deploy and its rights checks. The cost: an update of a library block reaches a flow only when the editor copies it again. `version` tells the editor that a newer one exists.
- A block holds config, not values; `read` is the level of `history`, which shows definitions too.

*If wrong:* a team that wants one change to reach every flow needs "update all" in the editor (copy and deploy each flow); the engine side stays as it is.

### 4. The second set of blocks (spec 06 0.2.25)
Added: what a flow on a broker needs and the engine could not do with its blocks. Each block has a port for every parameter, typed defaults and `port_types` in the catalog, and rows in `docs/flow-blocks.md`. The catalog has 55 types (36 before).

**Readers** (`src/readers.rs`):
- `load_value`: one read of a point's stored value. Fields `key` (port `in.key`, scope `key_scope`), `interval_ms`, `auto_run` (default true), `enabled`; input `trigger`; outputs `out` (the value with its quality and time), `ok`, `error` (`{event, id, code, message}`), `running`, `last_run`.
- `list_children`: the children of a node as a list of rows `{name, path, type?, display?, is?, unit?, writable, has_children}`, at most 1000 (more: `error` `resource_exhausted`). Fields `path` (port `in.path`, scope `path_scope`) and the same behaviour fields and outputs.
- Both are sources for §1: their static key is checked as a source, their scope as a scope, at deploy and for `watch`/`ports`/`preview`. A refused key from the port is an `error` event with `invalid_parameter`.
- **`list_children` reads the children (security review 2026-11-10).** A row shows a child's name, type, display, unit and whether it is writable. So the deployer, and every caller of `watch`, `ports` and `preview`, must read `<path>/*` as well as `<path>`, and for a scope `<scope>/*` as well (`downstream/l/**` → `downstream/l/*/**`), by the grant walk of §1: one child that is denied refuses the block, and a reader of the folder alone is refused. Chosen over filtering rows at run time by the deployer's grants: the engine keeps no grants after a deploy (ADR 0008), and a row that silently goes missing is harder to see than a deploy that is refused. A deny below the children does not matter: the rows are one level.
- A read is no command, so the start rule of §2 does not apply to `auto_run`: a reader reads at the start, and when its key changes. `trigger` still ignores a sample born at the start (the start read covers it). The latest read wins; a read without an answer after 5 s is `error` `timeout`. `load_value` reads the broker's value storage: a point that has no stored value is `not_found`.
- The `trigger` action (§2) is for command blocks only. A reader has no button yet.

**Text:** `substring` (`start`, `length`, by characters), `replace` (`from`, `to`; plain text, every occurrence), `split` (`separator`; a list of at most 1000 texts), `join` (`separator`). Results stay within 4 KiB (ADR 0032 §11); a longer one is `null` with quality `bad`.

**Data:** `make_object` (a map of its named inputs: a map argument for an action), `make_array`, `get` (`path` `a.b.0` into maps and lists), `stats` (a list's `min`, `max`, `avg`, `sum`, `count`).

**Events and state:** `changed` (`on_change`), `rising_edge`, `falling_edge` (`on_edge`), `counter` (`step`, `initial`, `reset`), `toggle` (`initial`, `reset`), `sample_and_hold` (`in`, `trigger`), `select` (`index`). These are what feeds `trigger` of §2. They follow the start rule: a sample born at the start gives the block its value and fires nothing, so `variable → rising_edge → trigger` does nothing at deploy while `alarm.out → rising_edge → trigger` fires on the first real alarm (for `rising_edge` nothing before counts as false). `counter` and `toggle` keep their state across a hot swap.

**Time:** `debounce` (the last value after `ms` without another) and `throttle` (the first at once, then the latest at the end of each `ms`). They have a clock only while a value waits (a quarter of `ms`, 5 to 50 ms), so the value goes out at most that much late.

**Numbers from a port are bounded (security review 2026-11-10).** `debounce.ms` as NaN reached `Duration::from_secs_f64` and panicked the node task. Rules now: (1) a block never takes a float that is not finite as a number (`num`: NaN, ±inf, and the texts `NaN`/`inf`), from a port or from the config; (2) a sample on a parameter's port that is such a float is not stored, the last good value stays; (3) `debounce`/`throttle` `ms` falls back to 500 when it is no number and is clamped to 0 … 3 600 000; `substring` `start` below 0 is 0 and `length` is at most 4 KiB; `select.index` is a whole number within the inputs or gives `null`; `counter` keeps its count when a step would leave the finite numbers; `get.path` longer than 4 KiB names nothing (a value nests at most 32 deep, README rule 6); `split` gives at most 1000 parts, `join` and `replace` at most 4 KiB; (4) `interval_ms` of the command blocks and readers, and the older `period_ms`, `size_s`, `ms` (ADR 0038 §5a), already took only a finite number in range. The runtime now calls `tick_every`, `first_tick_now` and `state` under its panic guard too, as it did `start`, `input` and `tick`: a panic there ends the run and the supervisor restarts it. Tests: `numbers_from_ports_are_bounded`, `interval_from_a_port_is_bounded` (NaN, ±inf, negative, huge, text).

**Left out, and why.**
| Candidate | Why not now |
|---|---|
| `json_parse`, CSV parser and writer, table to JSON | Principle 5 keeps `serde_json` to user files, and the flow crate has no JSON parser. A parser for values from a port needs a size and depth bound and an owner decision on the dependency. |
| `to_number`, `to_string`, `parse_number` | The variables do it: a `number` or `string` block converts what comes on `in`. |
| `string_format`, `format_number`, `trim`, `left`, `right` | `concat`, `round.text` and `substring` cover the common cases; a format language is a design of its own. |
| `now`, `format_time`, `time_range`, the date blocks | They need IANA time zones. `wyrm-schedule` has the bundled tzdb; whether the flow crate may depend on it is an owner decision. |
| Table blocks (`table_filter`, sort, group by, join, rollup, aggregation, …) | WYRM has no table value. A list of maps (`list_children.out`) with `get`, `stats`, `length` and `expression` covers reading a column; a table type comes with DQL results in flows, if at all. |
| `timer`/`interval` trigger source | `timer` exists; `interval_ms` on the block is the direct way. |
| `min_max_avg` | It is `stats`. `row_count` is `length`. |
| `regexp` in `case`, `router`, `event_gate`, `catch_error`, a block per table row, statistics (median, mode, deviation), trigonometry, `power`, `root`, `log`, `factorial`, `bound` | `expression` (rhai) computes all of the math; no bounded regex engine in the crate (ADR 0038 §8); routing, event and error blocks wait for a design of their own. |
| Browser, file, zip, history and project blocks | They belong to a page, not to a broker. History in a flow is its own design (DQL, ADR 0025). |

## Deferred
- **Dynamic command targets** (`set.path`, `invoke.path`/`action` from a port): §1a. Needs pattern proofs in spec 04.
- **A reader's button**: the `trigger` action for `load_value`/`list_children`, with read rights.
- **Library blocks by reference** (a flow that follows the library's newest version): §3 chose copies.
- **A row for an instance** in `watch` (its fields as one node): the editor maps them from the block's definition.
- **An echo for every instance input fan-out**: an instance input's output is the echo of its first inner input only.
- **`run_on_start` on a port**, and a start run that waits for bound arguments by cause instead of 250 ms.
- **The blocks of the table above.**
- **MCP and `wyrm-agent`** do not know the new actions (`trigger`, the library) by name; they reach them as any action.

