# ADR 0033 — `wyrm-agent`: a command line for operators and AI assistants

**Status:** accepted · 2026-11-01 (owner: "the agent is what you run locally from the CLI to do things: a tool for you").

## Context
The `agent` driver (ADR 0005) is an LLM inside the broker. The owner wants a tool that an AI assistant working on a workstation (Claude Code) runs to work on the broker network: create a device through the nodes' actions, set up history and upstream storage, deploy a dataflow that transforms points and writes a control value to another link. `wyr` talks Zenoh with an admin key; the demo's sites have none, and a key is the wrong identity for a person or an assistant. `wyrm-mcp` serves MCP clients over stdio.

## Decision
1. **`wyrm-agent` is a binary of `links/agent`** (feature `cli`). It logs in to a gateway as a user and uses its WebSocket (`wyrm-gateway-client`). The user's role decides everything; the gateway reaches downstream sites, so one gateway drives a chain of brokers.
2. **JSON lines out**, so an assistant reads the answers without parsing text.
3. **Plans**: `run <plan>` checks each step against the live `~meta` (action, argument schema, value bounds, through `wyrm_mcp::check`) and prints what it would do; `--apply` runs the steps in order and stops at the first failure. A step on a node an earlier step creates is checked when it runs. `unless` makes a plan safe to run again; `deploy` raises the flow's version itself; `wait` and `expect` let a plan prove its own result.
4. **The password only from the environment** (`WYR_GATEWAY_PASSWORD`), never an argument.
5. **Skill** `.claude/skills/wyrm-agent` tells an assistant in this repository how to use it.

## Found on the way
A flow deployed from an upstream site with a command target was refused: the deploy request itself was trusted (upstream keys, ADR 0018), but the engine checked the deployer's proofs with the admin keys only. The proofs of targets are now checked with the upstream keys as the links and storage trust them (`EngineStart::proof_keys`). e2e `chain_of_three_brokers` deploys such a flow from central.

A second refusal followed once the flow had a source: the engine knew an upstream key with the scope `dataflows` only, so the deployer's `auth` lost its grants on `downstream` and the source check (ADR 0031, FLOW-1) refused. The engine now knows the upstream keys also with the scopes `downstream` and `storage` give them; a request to the engine is still authorized within `dataflows` only, and only the deployer's rights on sources and targets are kept. The e2e flow has a source too.

*If wrong:* nothing is widened: a proof still has to be a token of the same subject at the flow's `maxperm` on that exact target, from a key the target itself trusts.
