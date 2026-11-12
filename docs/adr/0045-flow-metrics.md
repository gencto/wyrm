# ADR 0045 — Flow metrics in `~val`

Status: accepted (2026-11-12; decisions delegated under ADR 0029).

## Context

A deployed flow shows only its state in `dataflows/<id>/~val`:
`{state, error?, version, since, deployed_by?}` (spec 06). `running` says the node
tasks exist, not that samples reach them, that the inboxes keep up or that the
commands get answers. An operator who asks "does this deployment work?" has to
open a `watch` (ADR 0038), which needs read rights on every source and target and
shows values, not totals. The runtime already counts the samples an inbox drops
(`runtime::Inbox::dropped`), but nobody publishes the count.

Two limits shape the answer:

- `~val` of `dataflows/**` has watchers: gateway users (Studio follows every flow's
  `~val`), historian watches and peers upstream. A value that changes every second
  per flow would reach all of them.
- The runtime's hot path (one task per node, a sample per message) must stay free of
  locks and allocation.

## Decision

### 1. `~val.stats`

`~val` gets one more text key, `stats` (additive: old readers ignore it):

```
"stats": {
  "nodes": uint,          // nodes of the compiled flow, custom blocks expanded
  "edges": uint,          // edges of the compiled flow
  "samples_in": uint,     // samples the nodes took in
  "samples_out": uint,    // samples the nodes sent on a wired output
  "dropped": uint,        // samples the inboxes dropped (policy.overflow)
  "restarts": uint,       // restarts after a node panic
  "commands": {"sent": uint, "ok": uint, "error": uint},
  "last_sample_t": uint?  // µs, when a node last took in a sample; absent before
}
```

- `samples_in` counts each sample a node takes from its inbox when it came from an
  edge, or from the node's own source (`subscribe`, `liveliness`, `const`, and the
  "owner gone" mark of a `subscribe`). Internal messages are not samples: a
  command's or a reader's answer, a reader's own read request and `~act/trigger`.
- `samples_out` counts each sample a node sends on an output that has at least one
  edge (once, however many edges leave it). Writes of `publish`, `set` and `invoke`
  leave the flow through `commands` (or the published node), not here.
- `commands` counts the events `sent`, `ok` and `error` of the `invoke` and `set`
  blocks (spec 06 0.2.23). `error` includes a run refused before it was sent
  (`busy`: the call queue is full), so `ok + error` may exceed `sent`.
- `dropped` counts the inbox drops of `drop_oldest`/`drop_newest` and of a source
  that pushes into a full inbox under `block`. A `publish` that skips a sample while
  its writer is busy is not an inbox drop and is not counted.

The counters are atomics (`runtime::FlowStats`, `Relaxed`), shared by the node
tasks of one run: an increment per sample and one clock read per sample taken in,
no lock, no allocation. A node task knows at start whether its node is a command
block, so only those look at their event ports.

### 2. When the counters reset

The counters belong to a run that an operator or a deploy started:

- a new set at each deploy (also a hot swap and every stored flow that the engine
  deploys again at its start, so at every broker start and every ACL rebuild,
  ADR 0006), at `start` and at `reload`;
- kept across the supervisor's restart after a node panic (`restarts` grows);
- kept, frozen, while the flow is stopped or in `error`: the last totals stay
  visible;
- a deploy that does not compile changes nothing: the running version keeps its
  counters.

### 3. When `~val` is published

- A state change (deploy, start, stop, reload, error, restart) publishes `~val` at
  once, as before, with the counters of that moment.
- Between state changes one engine-wide clock looks at every flow once per period
  and publishes a flow's `~val` only when its counters differ from what its last
  `~val` carried. An idle or stopped flow publishes nothing.
- The period is `FlowHost::set_stats_every`. `wyrmd` sets it to
  `metrics_interval_ms` (the `sys` metrics period, default 10 s), and never below
  5 s. Without a setting the engine uses 10 s.

So a busy flow sends at most one more `~val` per period, and an idle site sends
none.

- A draft that does not compile shows `state: 2` and its `error` while the old
  version runs (spec 06). The engine keeps that error with the flow
  (`FlowRt::refused`), so the counters' later `~val`s carry it too, until the next
  state change (deploy, start, stop, reload, restart). Without this, the first
  counters-only `~val` would hide the refusal.

### 4. Out of scope

Per-node counters (rates per edge, per-node drops) would grow `~val` with the flow
and change it on every sample of any node. They stay out; `~act/watch` and
`~act/ports` already show per-node values to a caller with the rights.

## Consequences

- An operator sees in one value whether samples arrive (`samples_in`,
  `last_sample_t`), whether the flow keeps up (`dropped`) and whether its commands
  work (`commands.ok` against `commands.error`), with only read rights on the flow.
- Gateway subscribers and historian watches of `dataflows/**` get at most one more
  sample per busy flow per metrics period. A historian watch that records a flow's
  `~val` now records its counters too.
- Counters reset at every broker restart and ACL rebuild: they describe the current
  run, not the life of the flow. Long-term totals belong to a historian watch.
- `last_sample_t` changes with every sample, so a flow that keeps receiving always
  publishes once per period, even when the other counters hold still.
- The clock is one task per engine. A stop of the engine cuts it first, so it never
  delays the release of the flow store.
- Tools: `wyrm-mcp` returns `stats` with a flow's state. Studio and `wyr flow` do not
  show it yet.

## Alternatives

- **Separate nodes `dataflows/<id>/stats/*`.** Rejected: more keys to declare and
  re-declare per flow, more subscriptions for a UI, and the same rate question.
- **Publish every second.** Rejected: every watcher of `dataflows/**` would get one
  sample per flow per second whether anyone looks or not.
- **An action `~act/stats` instead of a value.** Rejected: an operator wants to see
  the counters next to the state, in the tree and in the historian, without polling.
- **Counters across runs (persisted).** Rejected: the broker would write flow
  traffic into its control-plane store; a run's counters are enough to tell whether
  a deployment works.
