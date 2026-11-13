# ADR 0049 — What the agent link and the gateway need for the Studio Assistant

Status: proposed (2026-11-14). Design: canvas row *Assistant* (`AssistantAsk`, `Assistant`, `AssistantRun`, `AssistantDone`, `AssistantFailed`, `AssistantRights`, `AssistantDrawer`). Studio side: `studio/docs/design/specs/assistant.md`. Extends ADR 0005 (AI surface) and ADR 0033 (agent command line); closes `docs/studio.md` §10 items 1, 3, 5, 11, 12.

## Context

The Studio Assistant (phase 12, `docs/studio.md` §7.8) is a chat with the agent link (`links/agent`): `ask` streams the model's lines and its reads, the task list follows `tasks/*` `~val`, Reject and Cancel work. The boards show more than the broker can give today:

| Board shows | Broker today |
|---|---|
| The plan with every step, its arguments, level, check result and the model's *why* | The plan is in the task's `~state` document; the gateway has no op that reads documents (`ws.rs`: `meta`, `children`, `list`, `subscribe`, `history`, `set`, `invoke`, `check`) |
| **Approve** signs one token per ticked step with the user's rights | `approve {approvals}` wants one human `ptok` per request key, signed by the approver; a gateway user has no key. The action itself is level `config` |
| Unticked steps are left out | `approve` refuses unless *every* step that needs approval has a token (`missing approval for …`) |
| The assistant asks back with choice cards (`AssistantAsk`) | No tool for asking the user, no state for it, no `answer` |
| `WAIT` / `EXPECT` steps (the plan proves itself) | Agent plans hold `set`/`invoke` only; `wait`/`expect` exist only in `wyrm_mcp::gw::Step` (plans of `wyrm-agent run` / MCP `plan_run`) |
| Run card with the current step and its answer | `~val` of a task is `{state}`; per-step results are only in `~state` |
| *Try Slave ID 4*, *Undo the plan*, *Make a plan for 2 units* | Every `ask` starts from nothing |
| `@ modbus/tcp-line2` chips, the Explorer drawer about the selection | `ask {task}` takes text only |
| *Today 182 k of 1 M tokens*, *API key set · never shown* | The budget used is internal; secret names are not readable |
| A warning on a step (*Slave ID 3 was used by ahu-old*) with fixes | `propose` returns ok or an error, nothing in between |

## Decision

1. **Documents through the gateway.** A gateway op `doc {key, suffix}` (`suffix` ∈ `~state`, `~def`) answers a node's document with the rights of `list` on that node (the agent's `tasks` folder is `restricted`, so the asker or a config caller). Studio reads a task's record with it after every state change.
2. **Approvals through the gateway.** On `invoke(<agent>/tasks/<id>, approve, {steps: [i…]})` from a user, the gateway reads the task's plan (op 1), mints one user token per listed step for that step's key and level, exactly as `add_flow_proofs` does for flow deploys, and refuses (before anything is sent) when the user's grants do not reach a step. The token's `sub` is the user, so the agent's "approver = signer" check holds. Callers outside the gateway keep sending `approvals`.
3. **Approve at the step's level.** `approve` becomes level `write` on the task; what a person may approve is decided by the tokens (a token at `config` for a `config` step). An engineer with `config` on `downstream/modbus/**` approves a Modbus plan without `config` on the agent link.
4. **Partial approval.** `approve` accepts a subset: the steps without a token are marked `skipped` (log line `skipped by <sub>`), never run; a step the model marked `after: [n]` is skipped when a step it depends on is. `propose` takes `after` (default: the previous step on the same key prefix). Approval tokens are keyed by step index (`approvals: {"<i>": ptok}`), not by request key, so two steps on one key both work; the key form stays accepted.
5. **Asking back.** A model tool `ask_user {question, options: [{id, label, detail}], multiple?, free_text?}` (≤ 3 questions per turn, ≤ 6 options each, options must name things the model read). The task goes to a new state `awaiting_answer` (`wire_enum!` row in the task states; Studio maps it). `tasks/<id>/~act/answer {answers: {<question>: [<option id>] | text}}` (level `write`, asker or config) resumes the model with the answers. `~state` carries `questions[]`.
6. **Proof steps.** Agent plans take the steps of `wyrm_mcp::gw::Step`: `wait {key, timeout_s}`, `expect {key, equals | min/max | changes, timeout_s}`, `sleep`. They need no approval (read). The plan format of `~state.plan[]` becomes the `wyrm-agent run` format, so **Save as a plan** is the plan as it stands.
7. **Progress in `~val`.** A task's public `~val` becomes `{state, step, of, last}` (`last` = `{n, ok, text}` of the latest finished step), published at each step. `~state` keeps per-step `result` (`ok | failed | skipped`, text, time).
8. **Checks and warnings on proposed steps.** `propose` answers `{ok, check, warn?}`: `check` = `now` (checked against the live tree) or `at_run` (depends on an earlier step); `warn` = text the model must show (a slave id in use, a value at a limit). Studio draws `warn` on the step; the model offers fixes as an `ask_user`.
9. **Follow-up asks and context.** `ask {task, parent?, context?: [key…]}`: `parent` hands the model the parent task's ask, plan and results (a retry, an undo, the same for more rows); `context` are keys the person attached (`@` chips, the Explorer selection), read first and within the asker's rights. *Undo* is a follow-up ask the model plans like any other; nothing is reversed automatically.
10. **What it may do, readable.** The agent root shows `budget_used_today` (u64, read). `sys/links/<id>` shows `secrets` (names only, level `config`), so Studio can say *set* / *not set* for `api_key_ref` (`docs/studio.md` §10 item 12).

## Consequences

- One gateway op (`doc`), one gateway rewrite of `approve` (like flow proofs), and agent link changes in `store.rs` (task schema: `questions`, `after`, per-step `result`; old tasks read with defaults) and `lib.rs` (`ask_user`, `answer`, `awaiting_answer`, `wait`/`expect`, `~val` progress).
- `docs/studio.md` §10 items 1, 3, 5, 11, 12 close when this is built; §7.8's "built now" paragraph is replaced by `studio/docs/design/specs/assistant.md`.
- e2e: ask → ask_user → answer → plan → partial approve (one step skipped, its dependant skipped) → wait/expect → done; approve refused for a user without the level; `doc` refused without `list`.

## Not decided here

- A second model for the Assistant (Claude through the user's own connector, ADR 0041, instead of the agent link's API key). The Studio screens stay the same; only who writes the plan changes.
- Generated views in the chat (A2UI, `specs/genui-views.md`): a later card type.
