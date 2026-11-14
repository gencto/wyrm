# Assistant chat

Boards (canvas row *Assistant*, y 9700): `AssistantAsk` (1 · it asks back), `Assistant` (2 · plan to approve, clickable: answers, ticks, Slave ID fix, Approve → run), `AssistantRun` (3), `AssistantDone` (4 · done, and do it again), `AssistantFailed` (4 · stopped), `AssistantRights` (what it may do), `AssistantDrawer` (in Explorer, about the selection, ⌘J). Broker side: **ADR 0049** (proposed). This spec replaces the "Built now" paragraph of `docs/studio.md` §7.8; the boards win for what is visible.

## 1. What is built and what differs

| Board | Built now (phase 12) | Missing in Studio | Needs from the broker |
|---|---|---|---|
| Task list (Now / Today / Earlier, state pill per task) | `tasks/*` with live states, selection | grouping by day, `owner` and short result under the name (`done · read only`, `rejected by olena`, `failed at step 3`) | `doc` (ADR 0049 §1) for owner, result, step |
| Conversation: ask, model lines, `read · …` chips, `nothing changed` | ask, `text`, `tool` rows as read chips, `state` rows — only for asks made in this session | the record of older tasks (from `~state.log`), the line *nothing changed* when a turn only read | §1 |
| `ChoicesCard` (3 questions, options with detail, *Write the plan*, *Or answer in your own words*) | — | the card, the answer line *from the card* | §5 `ask_user`, `awaiting_answer`, `answer` |
| `PlanCard` (state line, Show/Hide steps, the note about grey *why* lines) with `PlanStepCard`s (n, verb, action, key, level badge, args read-only via `param_form`, check line, *why*, tick on config steps, warning with fixes) | a note instead of the plan; closing card says what the task waits for | the whole card | §1 plan, §6 wait/expect, §8 `check`/`warn` |
| **Approve n changes and run**, Reject, the line *Signs one token per ticked step…* | Approve disabled with the reason; Reject, Cancel work | ticks, the count in the label, Approve enabled | §2 approvals through the gateway, §3 level, §4 partial |
| `RunCard` (n · step · result, *stops at the first step that fails*) | — | the card | §7 progress in `~val` |
| `ResultCard` (device facts, points with values and tags, Open in Explorer, Trend, Save as a plan, *Same for more units?* rows → *Make a plan for 2 units*) | — | the card; Save as a plan (download JSON for `wyrm-agent run`); the rows table | §6 (plan format), §9 `parent` |
| `StoppedCard` (code, what it read, three ways out with tags *1 change* / *2 changes* / *nothing*) | — | the card; each way out is a follow-up ask | §9 `parent` |
| Composer with `@` chips and *+ from Explorer*, hint per state | text box, disabled with a reason when there is no agent | chips, the per-state hint | §9 `context` |
| What it may do: This task facts, What it read, Who approves (3 modes), prefixes as chips with *+ prefix*, Model, Today, API key, Sent to | `cfg` keys as facts, reads of this session | modes as a picker, prefix chips (edit = `sys/links/<id>` edit params, config), *Today* with used / budget, *set / not set* | §10 `budget_used_today`, `secrets` |
| Explorer drawer (⌘J): ask about the selection, *What I found* rows, mini timeline, audit line, suggested step, *Approve and run*, *Ask ivan first* | — | the drawer | §1, §2, §9 |

Copy fix: the board's third approval mode says *Never — everything runs without a person*. The agent's `never` still asks a person for every `config` step (`ApprovalMode::Never` = like `config`). Studio says **Never — write steps run at once; config steps still wait for a person**.

## 2. Order of work
1. Read the record (`doc`, §1): task list details, old conversations, `PlanCard` read-only (no ticks, Approve still disabled).
2. Approve through the gateway (§2–4): ticks, label count, Approve enabled, Reject with reason.
3. Progress (§7): `RunCard`, then `ResultCard` and `StoppedCard` from the per-step results.
4. Asking back (§5): `ChoicesCard`, state `awaiting_answer` in the pill and the list.
5. Follow-ups and context (§9): ways out, *Make a plan for n units*, `@` chips, *+ from Explorer*.
6. What it may do (§10) and the Explorer drawer.

Each step ships when its broker part is merged; before that the board's part is not drawn (no disabled promises), except Approve, which keeps today's disabled state with its reason until step 2.

## 3. Cards
A closed catalogue in `ui/lib/assistant/`, each a dumb widget with its own Vm (`data-driven-widgets`); the connector maps `AgentTask` + `TaskEvent`s to a list of card Vms in order. New models through `frx add-model`: `TaskQuestion {id, text, options, multiple, freeText}`, `TaskOption {id, label, detail}`, `StepResult {n, result, text, time}`; `PlanStep` gains `n`, `verb` (`set | invoke | wait | expect | sleep`), `check` (`now | at_run`), `warn`, `after`; `TaskState` gains `awaitingAnswer` and `skipped` results (`frx add-enum` / `add-field`).

- **ReadTraceCard**: one chip per `tool` event, `read · <tool> <short key>`; ends with *nothing changed* when the turn proposed nothing.
- **ChoicesCard**: per question a group of option tiles (radio, or checkboxes when `multiple`), the detail under each label, border `accent` when picked; *Write the plan* → `answer {answers}`; typing in the composer instead sends `answer` with text. After answering, the card folds into one line *from the card: …*.
- **PlanCard**: header `Plan · n steps`, state line (`awaiting approval · checked` amber; `approved by <who> · k tokens` teal), Show/Hide steps. **PlanStepCard**: number ring (ember when it changes plant), verb chip (INVOKE ember, others grey), action, full key in mono, level badge (`config` coral-soft, `write`, `read` grey), args through `param_form` read-only (a field with a warning gets the warn border), the check line (`✓ …` teal, `◷ checked when it runs …` grey), `why: …` grey, a tick on steps that need approval, and the warning box with the fixes the model offered (each fix = `answer`).
- Approve bar: **Approve n changes and run** (n = ticked; disabled at 0), Reject (asks a reason), the line *Signs one token per ticked step with your rights (<role>). Unticked steps are left out.* A step that depends on an unticked one shows *skipped: needs step k*.
- **RunCard**: rows `n · step` + result (`running…` ember spinner, ok teal, failed coral, waiting grey); note `stops at the first step that fails` / `all steps passed · 41 s` / `stopped · steps 1–k stay done`.
- **ResultCard**: the facts the last steps produced (values of the keys the plan touched, read live), *Open <node> in Explorer*, *Trend <point>* (opens `specs/trend.md`), **Save as a plan** (the plan in `wyrm-agent run` format, saved through `file_selector`), and, when the model offers it, the rows table (*Same for more units?*) whose *Make a plan for n units* is `ask {parent, task, context}` with the rows as text.
- **StoppedCard**: *Stopped at step k · <code>*, what it read about the failure, and the ways out as tiles with tags; picking one sends a follow-up ask (`parent` = this task).

## 4. Composer and context
- Hint per state: `planning` *Answer, or ask something else…*; `awaiting_approval` *Ask to change the plan, e.g. "skip step 4"…*; `running` *You can write while it runs…*; `done` *What next?*; `failed` *Tell it what you know about <node>…*.
- `@` chips: the Explorer selection when the tab opened from Explorer, chips added by *+ from Explorer* (a key picker); sent as `context`. Removing a chip removes the key.
- A message while a task waits for approval asks for a new plan in the same task (`ask {parent}`); the old plan is shown as *replaced*.

## 5. Explorer drawer (⌘J)
Right drawer 420 over Explorer, header `Assistant · tasks/<id>`, *Open full* (Assistant tab, same task), ×. The ask starts with the selected node as a chip. Cards are the same catalogue in compact density; the suggested step uses `PlanStepCard` with **Approve and run** and a second button the model may offer (*Ask ivan first* = draft a message, never sent by Studio). The mini timeline is `Trend` compact on the point with the audit marks (`sys/audit/<link>`, config).

## 6. Data and calls
| UI | Read | Call |
|---|---|---|
| Task list, record | `tasks/*` `~val {state, step, of, last: {n, ok, result}}` (`result`: `ok`, `failed`, `skipped`; no text: `~val` is public); `doc(tasks/<id>, ~state)` on each change. The RunCard takes a row's text from `~state.plan[n].result.message` | — |
| Ask | — | `invoke(<agent>, ask, {task, parent?, context?})` (stream) |
| Answer | `~state.questions[]` | `invoke(tasks/<id>, answer, {answers})` |
| Approve | `~state.plan[]` | `invoke(tasks/<id>, approve, {steps: [n…], plan: planHash(plan)})` — the gateway adds the tokens. A user who is not the asker and has no `config` on the agent link ticks every step that changes something: an unticked one is skipped |
| Reject / Cancel | — | `reject {reason}`, `cancel` |
| What it may do | agent root `cfg`, value `budget_used_today`; `invoke(sys/links/<id>, secrets)` (names, config) | `sys/links/<id>` edit params (config) for modes and prefixes |

Errors follow `errors.md`: a refused approve names the step and the right missing (*step 4 needs config on sys/history/**; you have write*); a lost stream re-reads the record instead of retrying the ask.

## 7. Checklist
- [ ] Record through `doc`; old tasks show their conversation.
- [ ] ChoicesCard and `awaiting_answer`.
- [ ] PlanCard with steps, levels, checks, why, warnings and fixes.
- [ ] Ticks, partial approve, dependants skipped, Approve through the gateway, refusal per step.
- [ ] RunCard from `~val`; ResultCard; StoppedCard with ways out.
- [ ] Save as a plan (`wyrm-agent run` format).
- [ ] Composer hints, `@` chips, + from Explorer.
- [ ] What it may do: modes, prefix chips, budget, secret set/not set; copy fix for *Never*.
- [ ] Explorer drawer ⌘J.
- [ ] `frx doctor`, `dart analyze`; goldens for the 7 boards.
