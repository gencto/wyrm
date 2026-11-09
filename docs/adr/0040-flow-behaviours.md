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
