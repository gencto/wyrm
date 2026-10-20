# ADR 0005 — AI surface: MCP over the tree, agent as a connector

**Status:** accepted · 2026-10-20

## Decision
- `tools/wyrm-mcp`: an MCP server over `wyrm-client` (stdio and HTTP) exposing `tree_list/resolve/meta`, `value_get/history`, `node_set/action_invoke` (always `dry_run` first; config-level only with `approval_id`), `profiles/device_models`, `flow_*`, `link_*`, `spec`. Runs with a service-account `ptok`; audit `origin=ai:<agent>`.
- `links/agent`: an ordinary connector exposing tasks as nodes (`tasks/<id>/~val` state machine `planning → awaiting_approval → running → done|failed`, `~act/approve|reject|cancel`). Uses an LLM + the same MCP tools + a device-model catalog under `pub/models/<vendor>/<model>`. Human approval is enforced by `ptok.maxperm`, not by prompt.
- Flow node `llm` for small in-flow tasks with token budget and caching.
- `wyr` gains dev commands: `new link|flow`, `dev` (hot-reload), `sim`, `replay`, `ai`, `mcp`. Repo ships `.claude/skills/wyrm-link` and `wyrm-flow`.

## Why
The tree is self-describing (`~meta` types, action param schemas, profiles, `resolve` filters), so the MCP layer is mechanical and the agent needs no privileged path. Safety comes from the existing authorization model, not from the model's behaviour.

## Phase
Iteration 9, after core, control-plane, flow and security.
