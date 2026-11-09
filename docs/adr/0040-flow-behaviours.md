# ADR 0040 — Flow behaviours: keys from a port, the action block, custom blocks

**Status:** proposed · 2026-11-09 (owner requirements of 2026-11-09 for the next round of the Studio dataflow editor: bind a block's output into the path of another block; the action block with behaviour fields; custom blocks; the blocks still missing; decided under ADR 0029). Reference: DGLux5 (`docs/dataflow/engine.md`, `dglux_flutter/lib/runtime/dsa_blocks.dart`): its service blocks take `path` as a field that a binding can drive, and have `invoke`, `interval`, `autoRun`, `onSent`, `onComplete`, `onError`. WYRM ports the function, not the names (ADR 0032 §3).

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
A node action dropped from the tree becomes an `invoke` block. The type keeps its name and its old behaviour; it gains what the DGLux `invokeAction` block has.

**Arguments are fields.** `args` stays one map. Each key is an argument: its value is the argument's constant, and the port `arg.<name>` replaces it with the last sample (the field rule of ADR 0038 §7: a typed value that a binding can replace). An argument without a constant is `null`. An argument is also an output `arg.<name>` (ADR 0038 §1). At most 64 arguments; a name is 1 to 128 bytes and does not start with `__`. The prefix `arg.` keeps arguments apart from the block's own ports: DGLux hides a clashing name behind a zero-width space, and WYRM does not do that. `"$in"` as a constant still stands for the last value on `in`. The catalog says `dyn_inputs: {param: "args", prefix: "arg.", default: [], keys: true}`: `keys` means the parameter is a map and its keys name the ports.

**Behaviour fields** (config, and a port each):
| Field | Port | Default | Meaning |
|---|---|---|---|
| `interval_ms` | `in.interval_ms` | 0 | Above 0: a run every period. 0 is off; else 100 … 86 400 000. A value from the port outside these is ignored. |
| `auto_run` | `in.auto_run` | `invoke`: false · `set`: true | `invoke`: a sample on `arg.<name>` that changes the argument runs the action. `set`: a value on `in` is written (today's behaviour). |
| `enabled` | `in.enabled` | true | False: nothing runs the block, the `trigger` action included. |

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

A sample with the mark on `trigger` only gives the port its value. A sample with the mark on `arg.<name>` only fills the argument. `interval_ms` counts from the start of the node (and from a change of the period, and from `enabled` going true): the first run is one full period later. So a deploy, a hot swap, a reload and a restart after a crash run no command through `trigger`, `auto_run` or `interval_ms`. Tests: `a_deploy_never_runs_a_command_through_the_new_behaviours` and `tests/commands.rs`.

`in` is not part of the rule: a variable wired to `set.in` or `invoke.in` still writes at deploy, as ADR 0038 §6 warns. Changing that would change deployed flows. A flow that must not act at deploy uses `trigger`.

This is the alternative ADR 0038 §7 refused ("a start mark carried through every block"), in a narrower form: one bool on a sample, set at five places and carried by the runtime, and it changes no existing port's behaviour. *Cost:* a point that has no value when the flow starts gives its first value with the mark, so a `trigger` bound to it misses that one sample.

**`dataflows/<id>/~act/trigger {node}`** runs one block once.
- Level `write` on `dataflows/<id>`. The caller's `auth` (spec 04) must also give `max(maxperm, write)` on the block's own target (`…/~act/<action>` or `…/~set`), by the same grant walk as §1. This is the level the deploy asks of the deployer's proof (`proves_targets`): the flow's token for the target carries up to `maxperm`, so a caller with less would run through the flow what it may not run itself (security review 2026-11-09). The compiler caps `maxperm` at `write` today (spec 06 step 7), so the level is `write`; the gate follows `maxperm` so it holds if that cap ever moves. The engine cannot see the target action's own declared level without a read of its `~meta`; the target checks the flow's token against that level itself, and that token never carries more than `maxperm`. The flow's token only says that the deployer could; a button is pressed by a person, and that person needs the right. No `auth`: `permission_denied`.
- `node` is an `invoke` or `set` of the flow (the catalog marks these types `trigger: true`); another node is `invalid_parameter`.
- Only a deployed, running flow: a stopped flow or a flow in error is `not_supported` ("the flow is not running"). A preview has no such action.
- The run goes into the node's inbox on an internal port, in order with its samples. It runs with the block's current arguments, whether `trigger` is wired or not. A disabled block ignores it.
- The responder SDK audits the call as every action, with the caller as its subject; the target audits the command it gets with the subject `flow:<id>`, as every flow command.

**Preview.** `set` and `invoke` in a preview are the same nodes without a client or a writer (`Sink::Capture`): they decide as a deployed node does, record what they would send in the row's `sinks`, fire `sent` and set `last_run`. They never fire `ok` or `error`, never set `result`, `out` or `running`: there is no answer, and a made-up `ok` would show a success that did not happen.

**Found on the way.** Two command blocks with one target could not be deployed: `proves_targets` checked the target's proof once per block, and a proof token is taken once (`jti`, spec 04 0.2.11). It now checks one proof per target key.

