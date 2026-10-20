# ADR 0008 — Flow engine trust and deploy proofs

**Status:** accepted · 2026-10-20

## Context
The flow engine (`crates/wyrm-flow`, responder for `wy/<site>/flows/**`) runs `invoke`/`set` sinks that command devices. Each flow acts with a `ptok` that the engine signs with its own key (`flows.key`, subject `flow:<id>`, `max = maxperm`, grants = the flow's command targets at `maxperm`). Links must trust that key, or flows cannot command anything. But if a `config` right on `flows/**` were enough to deploy a flow, anyone who may deploy flows could write to every device through the flow key: `config` on `flows/**` would become `write` on `down/**`.

## Decision
- **Who trusts whom.**
  - Links trust admin keys plus `ControlConfig.link_keys` = the flow key and the gateway key (ADR 0009). The admin responder (`sys/**`) trusts admin keys only: a flow may command devices, never the control plane.
  - The flow engine trusts admin keys plus the gateway key, **never the flow key**: flow tokens cannot deploy, start, stop or remove flows (no flow can widen itself).
- **`~def` is read-only.** `flows/<id>/~def` is served as a document; there is no `put` deploy, because a bare `put` carries no verified caller. Deploying goes through `flows/~act/deploy` only (level `config`, `ptok`, audit).
- **`deploy {def, proofs}`.** Before compiling, the engine checks (`crates/wyrm-flow/src/engine.rs`):
  1. `caller_covers`: `permissions.maxperm` ≤ the deployer's effective permission on the deploy action.
  2. `proves_targets`: for every command target of the definition (`command_targets`: full keys of `…/~act/<a>` and `…/~set`, relative keys resolved under `wy/<site>/`):
     - the target is an exact key under `wy/<site>/down/` (no `*`, no `$`, so no `sys/**`, no `flows/**`, no other site);
     - `proofs[target]` is a `ptok` for that exact key, verified by the engine's keys (admin keys and the gateway key, so admin- or gateway-signed);
     - the proof has the **same subject** as the deploy caller;
     - the proof gives at least `max(maxperm, write)` on that key.
  Any failure is `permission_denied` (or `invalid_parameter` for a bad target) and nothing is stored.
- **Client side.** `WyrmClient::proof(key)` (`crates/wyrm-client/src/lib.rs`) returns a token for one key from the client's token source; `wyr flow deploy` builds `{def, proofs}` with it (`tools/wyr/src/flow.rs::deploy_args`) and fails early if it cannot sign a proof.

## Consequences
- A flow can do on a device only what its deployer could do there at deploy time, and only on the keys the definition names.
- Command targets are static. A flow cannot compute target keys at run time or use patterns; a fan-out needs one sink per key.
- **Proofs are checked at deploy time only.** Stored flows redeploy on every engine start (every broker build, ADR 0006) without proofs. Revoking a deployer's rights does not stop or re-check a running flow; an operator must `stop`/`remove` it. **Accepted (owner decision 2026-10-21):** flows are infrastructure, like a PLC program, and keep running until an operator stops them. The flow store keeps the deployer's subject with each definition (`PutDef.by`, `FlowStore.deployers`, schema 3), and the flow `~val` shows it as `deployed_by` (spec 06, 0.1.4), so an operator can find the flows of a removed user.
- **Gateway users cannot deploy flows with command sinks yet.** The gateway mints a ptok per request and never hands tokens to the user, so a gateway user has no way to send `proofs`. Flows without command sinks need no proofs. Deploying with sinks currently needs a key holder (`wyr --key`).
- `caller_covers` is weak by itself (the deploy action already needs `config`); the per-target proofs carry the real check.

## Alternatives
- **Engine checks the deployer's grants from the deploy `ptok`.** Rejected: requester tokens are scoped to the request key (`flows/~act/deploy`), so they say nothing about the targets.
- **Links do not trust the flow key; flows forward the deployer's token.** Rejected: tokens live 5 min and flows run for months.
- **Separate flow key per deployer, trusted per link.** Rejected: key management per user, and every link reconfigured or restarted (`LinkConfig.admin_keys`) for every new deployer.
- **Allow wildcard targets with a wildcard proof.** Rejected for now: a pattern proof is easy to over-grant, and the flow token would then cover keys that appear later.
