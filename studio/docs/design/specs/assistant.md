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
A closed catalogue in `ui/lib/assistant/`, each a dumb widget with its own Vm (`data-driven-widgets`); the connector maps `AgentTask` + `TaskEvent`s to a list of card Vms in order. New models through `frx add-model`: `TaskQuestion {id, text, options, multiple, freeText}`, `TaskOption {id, label, detail}`, `StepResult {n, result, text, time}`; `PlanStep` gains `n`, `verb` (`set | invoke | wait | expect | sleep`), `check` (`now | at_run`), `warn`, `modelWarn`, `after`; `TaskState` gains `awaitingAnswer` and `skipped` results (`frx add-enum` / `add-field`). The suggestions of the ADR 0049 amendment: `TaskSuggestion {id, label, detail, changes, step?, rows}`, `TaskRow {key, label, detail}` (as in `wyrm_client`); `AgentTask` gains `replacedBy`, `review`, `reviewing`.

- **ReadTraceCard**: one chip per `tool` event, `read · <tool> <short key>`; ends with *nothing changed* when the turn proposed nothing.
- **ChoicesCard**: per question a group of option tiles (radio, or checkboxes when `multiple`), the detail under each label, border `accent` when picked; *Write the plan* → `answer {answers}`; typing in the composer instead sends `answer` with text. After answering, the card folds into one line *from the card: …*.
- **PlanCard**: header `Plan · n steps`, state line (`awaiting approval · checked` amber; `approved by <who> · k tokens` teal), Show/Hide steps. **PlanStepCard**: number ring (ember when it changes plant), verb chip (INVOKE ember, others grey), action, full key in mono, level badge (`config` coral-soft, `write`, `read` grey), args through `param_form` read-only (a field with a warning gets the warn border), the check line (`✓ …` teal, `◷ checked when it runs …` grey), `why: …` grey, a tick on steps that need approval, and the warning box: `warn` (the link's own finding) and `model_warn` (the model's words, shown with the label *the assistant says* and never as a check of the link), with the fixes the model offered: the suggestions with `step` = this step (each fix = a follow-up `ask {parent}` that replaces this plan; ADR 0049 amendment).
- **Secret arguments** (decided 2026-11-14, ADR 0029). An argument is masked (`••••••`) when the `~meta` of the step's node marks it as a password. When that schema is not known (`check: at_run`: an earlier step makes the node; or the meta cannot be read, e.g. outside the user's rights; or it does not describe the action), any argument may be a secret: every argument of the step is masked, with *Show arguments* to look at them, and none is written by *Save as a plan* (`secrets_left_out` names them). The record is read again after each step, so once the node exists its schema is read and only its secrets stay masked. The agent link's `secrets` action does not help here: it names the link's own secrets, not the parameters of other links.
- Approve bar: **Approve n changes and run** (n = ticked; disabled at 0), Reject (asks a reason), the line *Signs one token per ticked step with your rights (<role>). Unticked steps are left out.* A step that depends on an unticked one shows *skipped: needs step k*.
- **RunCard**: rows `n · step` + result (`running…` ember spinner, ok teal, failed coral, waiting grey); note `stops at the first step that fails` / `all steps passed · 41 s` / `stopped · steps 1–k stay done`.
- **Rights on the tiles**: a fix, a way out and *Make a plan for n units* are follow-ups (`parent`), so they need `write` on the agent and the user must be the asker of the task or have `config` on the agent's `ask` (ADR 0049 §9); otherwise the tile is shown and disabled with the reason. Every tile tag from `changes` carries *its guess* (`docs/agent.md`, AI-4); with `require_approval` `config` or `never` the StoppedCard puts that caution before the tiles. Model text (labels, details, `review`, `model_warn`) is plain text: no marks read, no links.
- **ResultCard**: the facts the last steps produced (values of the keys the plan touched, read live), *Open <node> in Explorer*, *Trend <point>* (opens `specs/trend.md`), **Save as a plan** (the plan in `wyrm-agent run` format, saved through `file_selector`), and, when the model offers it (a suggestion with `rows`), the rows table (*Same for more units?*) whose *Make a plan for n units* is `ask {parent, task, context}` with the ticked rows' labels as text and their keys as `context` (`askSuggestion`). The rows start unticked: the person picks the nodes (a pick sends model text as a new ask, AI-4). The board's editable rows and *+ Row* have no data behind them (a row is a node the model offers) and are not drawn.
- **Replaced plan**: the PlanCard's state line says *replaced by tasks/<id>*, there are no ticks and no Approve (also while `~val` still says it waits), and the card has *Open tasks/<id>*. The task list says *replaced by <id>* from `~val`, before the record is read.
- **StoppedCard**: *Stopped at step k · <code>*, what it read about the failure (`~state.review`; a spinner while `reviewing`), and the ways out as tiles (`~state.suggestions`) with tags from `changes` (*nothing* at 0); picking one sends a follow-up ask (`parent` = this task).

## 4. Composer and context
- Hint per state: `planning` *Answer, or ask something else…*; `awaiting_approval` *Ask to change the plan, e.g. "skip step 4"…*; `running` *You can write while it runs…*; `done` *What next?*; `failed` *Tell it what you know about <node>…*.
- `@` chips: the Explorer selection when the tab opened from Explorer, chips added by *+ from Explorer*; sent as `context`, cleared when the ask is taken. Removing a chip removes the key. Built: *+ from Explorer* adds the node selected in Explorer (of the site on screen); there is no key picker of its own yet.
- A message while a task is selected follows it (`ask {parent}`) when the user may (the asker, or `config` on the agent's `ask`); else it is a new task. While the task waits for approval, the new task replaces its plan (the hint says so); the old plan is shown as *replaced* (`replaced_by` in its `~val` and record; the broker refuses its approve). *New task* starts a task without a parent.

## 5. Explorer drawer (⌘J)
Right drawer 420 over Explorer, header `Assistant · tasks/<id>`, *Open full* (Assistant tab, same task), ×. The ask starts with the selected node as a chip. Cards are the same catalogue in compact density; the suggested step uses `PlanStepCard` with **Approve and run** and a second button the model may offer: the first suggestion without `step` (`~state.suggestions`). While the task is `awaiting_approval`, the button opens that suggestion's `detail` as a draft to copy (*Ask ivan first*: the message to ivan): Studio sends no `ask`, so the plan stays approvable, and nothing is sent to ivan. After the task has ended, the button is a follow-up ask like any way out (`askSuggestion`). The mini timeline is `Trend` compact on the point with the audit marks (`sys/audit/<link>`, config).

Built (step 6): ⌘J / Ctrl+J in Explorer opens and closes the drawer (`AssistantDrawerConnector`, the tab's own view-model); opening it puts the Explorer selection as the first `@` chip. The drawer shows the task selected in the Assistant (one selection for both), its conversation, the ChoicesCard, the PlanCard with its ticks and fixes, the RunCard, the StoppedCard, and the task's card with Approve and the second button. The second button leaves out a suggestion with rows (it needs ticks the drawer does not show). Not built: the *What I found* rows and the mini timeline. The rows have no data: the model's findings are its text, not structured rows. The timeline needs a compact `Trend` with audit marks, which is a separate piece of work. Explorer's inspector beside the drawer already shows the point's history.

## 6. Data and calls
| UI | Read | Call |
|---|---|---|
| Task list, record | `tasks/*` `~val {state, step, of, last: {n, ok, result}}` (`result`: `ok`, `failed`, `skipped`; no text: `~val` is public); `doc(tasks/<id>, ~state)` on each change. The RunCard takes a row's text from `~state.plan[n].result.message` | — |
| Ask | — | `invoke(<agent>, ask, {task, parent?, context?})` (stream) |
| Ways out, more units, fixes | `~val.suggestions` (count), `~val.reviewing`; `~state.suggestions[] {id, label, detail, changes, step?, rows?}`, `~state.review` | `ask {parent, task: "<label>. <detail>", context: [row keys]}` |
| Which card shows which suggestions | the PlanStepCard of step n: those with `step == n`, only while `awaiting_approval`; the ResultCard (`done`): those with `rows`; the StoppedCard (`failed`, not replaced, a step failed): all of them, with `review` and a spinner while `reviewing`; the drawer's second button: the first one without `step` (§5: a draft to copy while `awaiting_approval`). Picking any suggestion of a task in `awaiting_approval` with `ask {parent}` replaces its plan; only the fix tiles do that, and they say so (*replaces this plan*). With `require_approval` `config` or `never`, a picked suggestion's plan may write at once: the tiles show the model's `changes` as its guess, not as a check (`docs/agent.md`, AI-4). A task that failed keeps only what the review offered; a `done` task keeps what planning offered, so filter by `step` and `rows` | — |
| Replaced plan | `replaced_by` in `~val` and `~state` | — (approve is refused) |
| Answer | `~state.questions[]` | `invoke(tasks/<id>, answer, {answers})` |
| Approve | `~state.plan[]` | `invoke(tasks/<id>, approve, {steps: [n…], plan: planHash(plan)})` — the gateway adds the tokens. A user who is not the asker and has no `config` on the agent link ticks every step that changes something: an unticked one is skipped |
| Reject / Cancel | — | `reject {reason}`, `cancel` |
| What it may do | agent root `cfg`, value `budget_used_today` (watched while the panel is shown); `invoke(sys/links/<id>, secrets)` (names, config; without config the key is *not known*) | `sys/links/<id>` ▸ `update {params}` (config) for modes and prefixes: staged with the other changes, the whole params from the staged update or the newest revision (`history`), applied in Review |
| Trend of the ResultCard | the last key a step set or proved | Explorer: that point selected, the History tab (`OpenTrendAction`) |

Errors follow `errors.md`: a refused approve names the step and the right missing (*step 4 needs config on sys/history/**; you have write*); a lost stream re-reads the record instead of retrying the ask.

## 7. Checklist
- [ ] Record through `doc`; old tasks show their conversation.
- [ ] ChoicesCard and `awaiting_answer`.
- [ ] PlanCard with steps, levels, checks, why, warnings and fixes.
- [ ] Ticks, partial approve, dependants skipped, Approve through the gateway, refusal per step.
- [ ] RunCard from `~val`; ResultCard; StoppedCard with ways out.
- [ ] Save as a plan (`wyrm-agent run` format).
- [x] Composer hints, `@` chips, + from Explorer (the Explorer selection; no key picker yet).
- [x] Ways out, fixes on a step, *Same for more units?*, a replaced plan (step 5).
- [x] What it may do: modes, prefix chips, budget, secret set/not set; copy fix for *Never* (step 6).
- [x] Explorer drawer ⌘J (step 6; without *What I found* rows and the mini timeline).
- [ ] `frx doctor`, `dart analyze`; goldens for the 7 boards.
