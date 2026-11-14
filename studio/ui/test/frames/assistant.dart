import 'package:material_ui/material_ui.dart';
import 'package:ui/assistant/assistant_composer.dart';
import 'package:ui/assistant/assistant_drawer.dart';
import 'package:ui/assistant/choices_card.dart';
import 'package:ui/assistant/conversation.dart';
import 'package:ui/assistant/found_card.dart';
import 'package:ui/assistant/model_words.dart';
import 'package:ui/assistant/more_rows_card.dart';
import 'package:ui/assistant/plan_card.dart';
import 'package:ui/assistant/result_card.dart';
import 'package:ui/assistant/rights_panel.dart';
import 'package:ui/assistant/run_card.dart';
import 'package:ui/assistant/stopped_card.dart';
import 'package:ui/assistant/suggestion_tile.dart';
import 'package:ui/assistant/task_list.dart';
import 'package:ui/buttons/segmented_tabs.dart';
import 'package:ui/charts/trend.dart';
import 'package:ui/containers/fact_grid.dart';
import 'package:ui/indicators/status_pill.dart';
import 'package:ui/models/tone.dart';
import 'package:ui/overlays/search_palette.dart';
import 'package:ui/pages/assistant_page.dart';

import 'trend.dart' show trendFormat;

/// Board *Assistant* with a task that waits for approval: both changes
/// ticked. With [refusal] the last approval was refused and the task still
/// waits.
Widget assistantPlan({String? refusal}) => _assistant(
  plan: assistantPlanCard(ticks: const [true, true]),
  onTick: (_, {required ticked}) {},
  card: TaskCardVm(
    title: 'Plan',
    note: refusal == null
        ? 'Signs one token per ticked step with your rights (engineer). '
              'Unticked steps are left out.'
        : 'The approval was refused; the task still waits. $refusal\n'
              'Untick the step it names and approve the rest. When the plan '
              'is done, ask for the steps left out as a follow-up: they are '
              'approved then.',
    caution: refusal != null,
    buttons: const [
      TaskButtonVm(id: 'reject', label: 'Reject'),
      TaskButtonVm(
        id: 'approve',
        label: 'Approve 2 changes and run',
        primary: true,
      ),
    ],
  ),
);

PlanCardVm _folded(String state, Tone tone) => PlanCardVm(
  title: 'Plan · 3 steps',
  state: state,
  stateTone: tone,
  steps: assistantPlanCard().steps,
  open: false,
  showLabel: 'Show steps',
  hideLabel: 'Hide steps',
);

const _step1 = 'INVOKE add_device modbus/tcp-line2';
const _step2 = 'SET modbus/tcp-line2/ahu2/supply_sp';
const _step3 = 'EXPECT modbus/tcp-line2/ahu2/supply_sp';

/// Board *AssistantRun*: step 2 of the plan runs.
Widget assistantRun() => _assistant(
  state: 'running',
  tone: Tone.ember,
  plan: _folded('approved by olena', Tone.ember),
  run: const RunCardVm(
    title: 'Run · step 2 of 3',
    rows: [
      RunRowVm(n: 1, step: _step1, status: .ok, text: 'added ahu2'),
      RunRowVm(n: 2, step: _step2, status: .running, text: 'running…'),
      RunRowVm(n: 3, step: _step3, status: .waiting, text: 'waiting'),
    ],
    note: 'stops at the first step that fails',
  ),
  card: const TaskCardVm(
    title: 'running',
    note: 'The agent works on it. Cancel stops it; what was done stays done.',
    buttons: [TaskButtonVm(id: 'cancel', label: 'Cancel task', danger: true)],
  ),
);

/// Board *AssistantDone*: every step passed.
Widget assistantDone() => _assistant(
  state: 'done',
  tone: Tone.good,
  plan: _folded('approved by olena', Tone.good),
  run: const RunCardVm(
    title: 'Run · 3 steps',
    rows: [
      RunRowVm(n: 1, step: _step1, status: .ok, text: 'added ahu2'),
      RunRowVm(n: 2, step: _step2, status: .ok, text: 'ok'),
      RunRowVm(n: 3, step: _step3, status: .ok, text: '21.5'),
    ],
    note: 'all steps passed · 41 s',
    noteTone: Tone.good,
  ),
  result: const ResultCardVm(
    title: 'Result',
    facts: [('modbus/tcp-line2/ahu2/supply_sp', '21.5 °C')],
    note: 'The keys the plan touched, with their values now.',
  ),
  card: const TaskCardVm(
    title: 'done',
    note: 'The task is done. Its record keeps the plan and the log.',
    buttons: [
      TaskButtonVm(id: 'explorer', label: 'Open supply_sp in Explorer'),
      TaskButtonVm(id: 'save', label: 'Save as a plan'),
    ],
  ),
);

/// Board *AssistantFailed*: the run stopped at step 2, with the review and
/// the ways out; with [reviewing] the model still reads why.
Widget assistantFailed({bool reviewing = false}) => _assistant(
  state: 'failed or stopped',
  tone: Tone.bad,
  plan: _folded('approved by olena', Tone.bad),
  run: const RunCardVm(
    title: 'Run · 3 steps',
    rows: [
      RunRowVm(n: 1, step: _step1, status: .ok, text: 'added ahu2'),
      RunRowVm(
        n: 2,
        step: _step2,
        status: .failed,
        text: 'out_of_range: 21.5 is above max 21',
      ),
      RunRowVm(n: 3, step: _step3, status: .waiting, text: 'not run'),
    ],
    note: 'stopped · step 1 changed something and stays done',
    noteTone: Tone.bad,
  ),
  stopped: StoppedCardVm(
    title: 'Stopped at step 2 · out_of_range',
    message:
        'out_of_range: 21.5 is above max 21\n'
        'What was done before it stays done; nothing is reversed by itself.',
    reviewing: reviewing ? 'The assistant reads why it stopped…' : null,
    review: reviewing
        ? null
        : const ModelWordsVm(
            label: 'what the assistant read about it',
            text:
                'The point allows at most 21 °C. ahu1 runs at 21 with the '
                'same setpoint range, so 21 is likely what was meant.',
          ),
    waysLabel: 'Ways out',
    ways: reviewing ? const [] : _ways,
    note: reviewing
        ? null
        : 'A pick is a new ask. Its plan is checked and waits for your '
              'approval, step by step.',
  ),
  card: reviewing
      ? const TaskCardVm(
          title: 'failed or stopped',
          note:
              'The agent works on it. Cancel stops it; what was done stays '
              'done.',
          buttons: [
            TaskButtonVm(id: 'cancel', label: 'Cancel task', danger: true),
          ],
        )
      : null,
  askHint: 'Tell it what you know about supply_sp…',
);

const _ways = [
  SuggestionTileVm(
    id: 's1',
    label: 'Set 21 instead',
    detail: 'A new plan with one step: set supply_sp to 21, then the check.',
    tag: '1 change · its guess',
    tagTone: Tone.ember,
  ),
  SuggestionTileVm(
    id: 's2',
    label: 'Undo the plan',
    detail: 'A plan that removes ahu2 (step 1, reversed).',
    tag: '1 change · its guess',
    tagTone: Tone.ember,
  ),
  SuggestionTileVm(
    id: 's3',
    label: 'Leave it as it is',
    detail: 'ahu2 stays with its default setpoint.',
    tag: 'nothing · its guess',
  ),
];

/// Board *Assistant*, a step with the link's warning, the model's words and
/// a fix that replaces the plan; the composer holds an `@` chip.
Widget assistantFix() {
  final plan = assistantPlanCard(ticks: const [true, true]);
  return _assistant(
    plan: PlanCardVm(
      title: plan.title,
      state: plan.state,
      note: plan.note,
      steps: [
        const PlanStepVm(
          n: 1,
          verb: 'INVOKE',
          action: 'add_device',
          target: 'wy/plant/downstream/modbus/tcp-line2',
          level: 'config',
          changes: true,
          args: [('name', 'ahu2'), ('slave_id', '3'), ('poll_s', '5')],
          check: 'checked against the live tree',
          warn: 'unit 3 answers with exception 0x0B behind this gateway',
          modelWarn: ModelWordsVm(
            label: 'the assistant says',
            text:
                'ahu-old answered on unit 3 until March; the new box is '
                'likely unit 4.',
          ),
          fixes: [
            SuggestionTileVm(
              id: 'f1',
              label: 'Try Slave ID 4',
              detail: 'The same plan with slave_id 4.',
              tag: '1 change · its guess',
              tagTone: Tone.ember,
              note: 'replaces this plan',
            ),
          ],
          why: 'the unit the operator named, with the points of ahu1',
          ticked: true,
        ),
        ...plan.steps.skip(1),
      ],
    ),
    onTick: (_, {required ticked}) {},
    card: const TaskCardVm(
      title: 'Plan',
      note:
          'Signs one token per ticked step with your rights (engineer). '
          'Unticked steps are left out.',
      buttons: [
        TaskButtonVm(id: 'reject', label: 'Reject'),
        TaskButtonVm(
          id: 'approve',
          label: 'Approve 2 changes and run',
          primary: true,
        ),
      ],
    ),
    chips: const [('wy/plant/downstream/modbus/tcp-line2', 'modbus/tcp-line2')],
    askHint: 'Ask to change the plan, e.g. “skip step 4”…',
    askNote:
        'Sending asks for a new plan: this plan is replaced and can no '
        'longer be approved.',
  );
}

/// Board *AssistantDone* with *Same for more units?*: one row ticked.
Widget assistantMore() => _assistant(
  state: 'done',
  tone: Tone.good,
  plan: _folded('approved by olena', Tone.good),
  result: const ResultCardVm(
    title: 'Result',
    facts: [('modbus/tcp-line2/ahu2/supply_sp', '21.5 °C')],
    note: 'The keys the plan touched, with their values now.',
  ),
  more: const [
    MoreRowsCardVm(
      id: 's1',
      title: 'Same for more units?',
      detail: 'ahu3 and ahu4 answer on line 2 with the points of ahu1.',
      rows: [
        MoreRowVm(
          key: 'wy/plant/downstream/modbus/tcp-line2/ahu3',
          label: 'ahu3',
          detail: 'unit 5 · 14 points',
          ticked: true,
        ),
        MoreRowVm(
          key: 'wy/plant/downstream/modbus/tcp-line2/ahu4',
          label: 'ahu4',
          detail: 'unit 6 · 14 points',
        ),
      ],
      button: 'Make a plan for 1 unit',
      note:
          "The rows are the assistant's. Its plan for them waits for your "
          'approval.',
    ),
  ],
  card: const TaskCardVm(
    title: 'done',
    note: 'The task is done. Its record keeps the plan and the log.',
    buttons: [
      TaskButtonVm(id: 'explorer', label: 'Open supply_sp in Explorer'),
      TaskButtonVm(id: 'save', label: 'Save as a plan'),
    ],
  ),
  askHint: 'What next?',
);

/// A plan another task replaced: no ticks, no Approve, the way on.
Widget assistantReplaced() => _assistant(
  state: 'failed or stopped',
  tone: Tone.bad,
  plan: _folded('replaced by tasks/t-0143', Tone.bad),
  card: const TaskCardVm(
    title: 'replaced',
    note:
        'This plan was replaced by tasks/t-0143 and cannot be approved. '
        'Approve the plan of that task instead.',
    buttons: [
      TaskButtonVm(
        id: 'replacement',
        label: 'Open tasks/t-0143',
        primary: true,
      ),
    ],
  ),
  detail: 'replaced by t-0143',
);

/// Board *AssistantAsk*: the assistant asks back; one option is picked.
Widget assistantAsk() => _assistant(
  state: 'awaiting your answer',
  choices: const ChoicesCardVm(
    title: 'The assistant asks',
    questions: [
      ChoiceQuestionVm(
        id: 'q1',
        text: 'Which unit is AHU 2?',
        options: [
          ChoiceOptionVm(
            id: 'u3',
            label: 'Slave ID 3',
            detail: 'answers; ahu-old used it until March',
          ),
          ChoiceOptionVm(
            id: 'u4',
            label: 'Slave ID 4',
            detail: 'answers; no device has it',
            picked: true,
          ),
        ],
      ),
      ChoiceQuestionVm(
        id: 'q2',
        text: 'Which points do you want recorded?',
        multiple: true,
        options: [
          ChoiceOptionVm(id: 'supply', label: 'Supply temperature'),
          ChoiceOptionVm(id: 'return', label: 'Return temperature'),
        ],
      ),
    ],
    confirm: 'Write the plan',
    note: 'Or answer in your own words below.',
  ),
  card: const TaskCardVm(
    title: 'awaiting your answer',
    note:
        'The assistant waits for your answer. Nothing is planned before it. '
        'A restart of the broker ends a task that waits.',
    buttons: [TaskButtonVm(id: 'cancel', label: 'Cancel task', danger: true)],
  ),
);

Widget _assistant({
  TaskCardVm? card,
  StoppedCardVm? stopped,
  List<MoreRowsCardVm> more = const [],
  List<ChipVm> chips = const [],
  String askHint =
      'Ask for a change, or a question about the network (Cmd+Enter)',
  String? detail,
  String? askNote,
  RightsPanelVm? rights,
  ChoicesCardVm? choices,
  String state = 'awaiting approval',
  Tone tone = Tone.warn,
  PlanCardVm? plan,
  void Function(int n, {required bool ticked})? onTick,
  RunCardVm? run,
  ResultCardVm? result,
}) => AssistantPage(
  newLabel: 'New task',
  listNote: 'Each task is a node: agent/tasks/<id>',
  sections: [
    TaskSectionVm(
      label: 'Now',
      tasks: [
        TaskItemVm(
          id: 't-0142',
          title: 'Add ahu2 on line 2',
          state: state,
          tone: tone,
          detail: detail,
          selected: true,
        ),
      ],
    ),
    const TaskSectionVm(
      label: 'Earlier',
      tasks: [
        TaskItemVm(
          id: 't-0141',
          title: 'Why is boiler valve bad?',
          state: 'done',
          tone: Tone.good,
        ),
        TaskItemVm(
          id: 't-0131',
          title: 'Rename the S7 points of press 2',
          state: 'failed or stopped',
          tone: Tone.bad,
        ),
      ],
    ),
  ],
  onNew: () {},
  onTask: (_) {},
  title: 'Add ahu2 on line 2',
  status: StatusPillVm(label: state, tone: tone),
  taskKey: 'tasks/t-0142',
  events: [
    const ConversationEventVm(
      kind: .ask,
      text:
          'Add AHU 2 on line 2. It is unit 3 behind the line-2 gateway, '
          'same points as ahu1. Record its supply temperature every minute.',
    ),
    const ConversationEventVm(
      kind: .text,
      text: 'I looked at line 2. ahu1 has 14 points on tcp-line2.',
    ),
    const ConversationEventVm(
      kind: .reads,
      reads: ['read · tree', 'read · meta', 'read · get'],
    ),
    const ConversationEventVm(
      kind: .text,
      text:
          'Here is the plan: 5 steps, 3 of them change plant. '
          'Nothing runs until you approve.',
    ),
    ConversationEventVm(kind: .state, text: state, tone: tone),
  ],
  plan: plan,
  onTick: onTick,
  run: run,
  result: result,
  more: more,
  onRow: (_, _, {required on}) {},
  onMore: (_) {},
  stopped: stopped,
  onWay: (_) {},
  onFix: (_) {},
  choices: choices,
  onPick: (_, _) {},
  onAnswer: () {},
  card: card,
  onButton: (_) {},
  draft: '',
  askHint: askHint,
  askNote: askNote,
  askLabel: 'Ask',
  chips: chips,
  onChipRemove: (_) {},
  addChipLabel: '+ from Explorer',
  addChipReason: chips.isEmpty
      ? 'Select a node in Explorer first; it is added here as @ chip.'
      : null,
  onAddChip: () {},
  onDraft: (_) {},
  onAsk: () {},
  panels: const [
    TabItemVm(id: 'task', label: 'This task'),
    TabItemVm(id: 'rights', label: 'What it may do'),
  ],
  panel: rights == null ? 'task' : 'rights',
  onPanel: (_) {},
  rights: rights,
  onMode: (_) {},
  onRemovePrefix: (_) {},
  onAddPrefix: () {},
  facts: [
    const FactVm(label: 'Task', value: 'tasks/t-0142', mono: true),
    FactVm(label: 'State', value: state),
    const FactVm(label: 'Asked by', value: 'olena'),
    const FactVm(label: 'Events', value: '9'),
  ],
  readsLabel: 'What it read',
  reads: const [('tree', ''), ('meta', '× 2'), ('get', '')],
  panelNote:
      'Reading needs no approval. What it reads stays inside your rights '
      'and its own.',
);

/// The plan of [assistantPlan]: a config step, a step checked when it runs
/// with a warning, and a proof. [ticks] gives the changing steps a tick.
PlanCardVm assistantPlanCard({List<bool>? ticks}) => PlanCardVm(
  title: 'Plan · 3 steps',
  state: 'awaiting approval · 1 checked now, 1 when it runs',
  note:
      'The lines after “why” and under “the assistant says” come from the '
      "model; a warning on the yellow band is the link's own check. Read the "
      'key and the arguments of each step: they are what runs.',
  steps: [
    PlanStepVm(
      n: 1,
      verb: 'INVOKE',
      action: 'add_device',
      target: 'wy/plant/downstream/modbus/tcp-line2',
      level: 'config',
      changes: true,
      args: const [('name', 'ahu2'), ('slave_id', '3'), ('poll_s', '5')],
      check: 'checked against the live tree',
      why: 'the unit the operator named, with the points of ahu1',
      ticked: ticks?[0],
    ),
    PlanStepVm(
      n: 2,
      verb: 'SET',
      target: 'wy/plant/downstream/modbus/tcp-line2/ahu2/supply_sp',
      level: 'write',
      changes: true,
      args: const [('value', '21.5')],
      check: 'checked when it runs: an earlier step makes this node',
      checked: false,
      warn: "the value 21.5 is at the point's max (21.5)",
      note: 'needs step 1',
      ticked: ticks?[1],
    ),
    const PlanStepVm(
      n: 3,
      verb: 'EXPECT',
      target: 'wy/plant/downstream/modbus/tcp-line2/ahu2/supply_sp',
      level: 'read',
      args: [('equals', '21.5'), ('timeout', '10 s')],
      note: 'needs step 2',
    ),
  ],
);

/// Board *AssistantRights*: what the agent may do; a mode change is staged.
Widget assistantRights() => _assistant(
  plan: assistantPlanCard(ticks: const [true, true]),
  onTick: (_, {required ticked}) {},
  card: const TaskCardVm(
    title: 'Plan',
    note:
        'Signs one token per ticked step with your rights (engineer). '
        'Unticked steps are left out.',
  ),
  rights: const RightsPanelVm(
    modesLabel: 'Who approves',
    modes: [
      ModeVm(
        id: 'write',
        label: 'Every step',
        detail: 'A person approves each set and invoke. Recommended.',
        selected: true,
      ),
      ModeVm(
        id: 'config',
        label: 'Only config steps',
        detail:
            "Write steps run at once with the agent's own key; config steps "
            'wait for a person.',
      ),
      ModeVm(
        id: 'never',
        label:
            'Never — write steps run at once; config steps still wait for a '
            'person',
        detail:
            "The agent runs config steps only with a person's token, as in "
            '“Only config steps”. Text in the tree can steer the plan.',
      ),
    ],
    prefixesLabel: 'Where it may propose changes',
    prefixes: [
      ('wy/plant/downstream/modbus', 'downstream/modbus'),
      ('wy/plant/sys/history', 'sys/history'),
      ('wy/plant/dataflows', 'dataflows'),
    ],
    prefixesNote:
        'allowed_prefixes · outside them a step is refused at the check.',
    addPrefix: '+ prefix',
    facts: [
      FactVm(label: 'Model', value: 'claude-sonnet-5-5', mono: true),
      FactVm(label: 'Today', value: '182 k of 1 M tokens'),
      FactVm(
        label: 'API key secret',
        value: 'set · never shown',
        code: 'anthropic_api_key',
      ),
      FactVm(label: 'Sent to', value: 'api.anthropic.com', mono: true),
    ],
    note:
        'These are params of the agent link (needs config). A pick is staged '
        'and runs when you apply it in Review. Changing where the key is sent '
        'deletes the key; enter it again after.',
    staged:
        "A change of the agent's params is staged. It runs when you apply it "
        'in Review.',
  ),
);

/// Board *AssistantDrawer*: the Assistant over Explorer about the selected
/// node; the plan waits, and the second button is the model's draft.
Widget assistantDrawer() => Builder(
  builder: (context) => Stack(
    children: [
      const Positioned.fill(child: ColoredBox(color: Color(0xFF0E1113))),
      Positioned(
        top: 0,
        right: 0,
        bottom: 0,
        width: 420,
        child: AssistantDrawer(
          title: 'Assistant',
          taskKey: 'tasks/t-0141',
          openFull: 'Open full',
          closeLabel: 'Close (Cmd+J)',
          onOpenFull: () {},
          onClose: () {},
          events: const [
            ConversationEventVm(kind: .ask, text: 'Why is the valve bad?'),
            ConversationEventVm(
              kind: .text,
              text:
                  'The connection and plc1 are fine; only valve fails. Its '
                  'offset was changed 7 minutes before it went bad.',
            ),
            ConversationEventVm(
              kind: .reads,
              reads: ['read · tree', 'read · get', 'read · audit'],
            ),
          ],
          plan: const PlanCardVm(
            title: 'Plan · 1 step',
            state: 'awaiting approval · checked',
            steps: [
              PlanStepVm(
                n: 1,
                verb: 'INVOKE',
                action: 'edit',
                target: 'wy/plant/downstream/modbus/tcp-boiler/plc1/valve',
                level: 'config',
                changes: true,
                args: [('offset', '11')],
                check: 'checked against the live tree',
                why: 'it read well at 11 until the edit',
                ticked: true,
              ),
            ],
          ),
          onTick: (_, {required ticked}) {},
          card: const TaskCardVm(
            title: 'Plan',
            note:
                'Signs one token per ticked step with your rights (engineer).',
            buttons: [
              TaskButtonVm(id: 'reject', label: 'Reject'),
              TaskButtonVm(
                id: 'approve',
                label: 'Approve 1 change and run',
                primary: true,
              ),
            ],
          ),
          onButton: (_) {},
          secondLabel: 'The assistant suggests',
          second: const SuggestionTileVm(
            id: 's1',
            label: 'Ask ivan first',
            detail: 'Ivan, did you move valve to offset 12 at 03:05?',
            tag: 'nothing · its guess',
            note: 'a draft to copy · sends nothing',
          ),
          onSecond: () {},
          newTask: 'New task',
          onNewTask: () {},
          composer: AssistantComposer(
            draft: '',
            hint: 'Ask about what you see… (Cmd+Enter)',
            label: 'Ask',
            onDraft: (_) {},
            onAsk: () {},
            chips: const [
              (
                'wy/plant/downstream/modbus/tcp-boiler/plc1/valve',
                'modbus/tcp-boiler/plc1/valve',
              ),
            ],
            addChipLabel: '+ from Explorer',
            dense: true,
          ),
        ),
      ),
    ],
  ),
);

/// Board *AssistantDrawer* with *What I found*: the nodes the model read,
/// marked from their live values, and the mini timeline of the selected
/// point with the audit record on it.
Widget assistantDrawerFound() {
  // 02:12 … 03:12 UTC, a sample a minute; bad after 03:05 + 7 min
  final end = DateTime.utc(2026, 11, 14, 3, 30).microsecondsSinceEpoch;
  const minute = 60 * 1000000;
  final start = end - 60 * minute;
  final edit = end - 25 * minute;
  final samples = [
    for (var i = 0; i <= 60; i++)
      TrendSample(
        start + i * minute,
        start + i * minute < edit + 7 * minute ? 11.0 : null,
        q: start + i * minute < edit + 7 * minute ? .good : .bad,
      ),
  ];
  return Builder(
    builder: (context) => Stack(
      children: [
        const Positioned.fill(child: ColoredBox(color: Color(0xFF0E1113))),
        Positioned(
          top: 0,
          right: 0,
          bottom: 0,
          width: 420,
          child: AssistantDrawer(
            title: 'Assistant',
            taskKey: 'tasks/t-0141',
            openFull: 'Open full',
            closeLabel: 'Close (Cmd+J)',
            onOpenFull: () {},
            onClose: () {},
            events: const [
              ConversationEventVm(kind: .ask, text: 'Why is the valve bad?'),
              ConversationEventVm(
                kind: .text,
                text:
                    'The connection and plc1 are fine; only valve fails. Its '
                    'offset was changed 7 minutes before it went bad.',
              ),
              ConversationEventVm(
                kind: .reads,
                reads: ['read · tree', 'read · get', 'read · audit'],
              ),
            ],
            found: FoundCardVm(
              title: 'What I found · read only',
              note:
                  "The words are the assistant's. Each mark is the node's "
                  'live value now, read with your rights.',
              rows: const [
                FoundRowVm(
                  label: 'tcp-boiler',
                  detail: 'connected · 10.0.4.12:502',
                  node: 'modbus/tcp-boiler',
                  mark: .none,
                  markLabel: 'no value read',
                ),
                FoundRowVm(
                  label: 'plc1',
                  detail: '4 of 5 points good',
                  node: 'modbus/tcp-boiler/plc1',
                  mark: .good,
                  markLabel: 'good now',
                ),
                FoundRowVm(
                  label: 'valve',
                  detail:
                      'bad since 03:12 · exception 0x02 illegal data address',
                  node: 'modbus/tcp-boiler/plc1/valve',
                  mark: .bad,
                  markLabel: 'bad now',
                ),
              ],
              timelineLabel: 'valve · last 1h',
              timeline: TrendVm(
                title: 'valve',
                series: [
                  TrendSeriesVm(
                    id: 'valve',
                    name: 'valve',
                    color: TrendColor.byIndex(0),
                    unit: '%',
                    decimals: 0,
                    samples: samples,
                    overview: samples,
                  ),
                ],
                rangeStart: start,
                rangeEnd: end,
                windowStart: start,
                windowEnd: end,
                rollup: 'raw',
                endsNow: true,
                card: false,
                legend: false,
                hint: false,
                brush: false,
                plotHeight: 64,
                marks: [
                  TrendMark(
                    edit,
                    'user:ivan · invoke modbus/tcp-boiler/plc1/valve/~act/edit',
                  ),
                ],
                format: trendFormat,
              ),
              auditLabel: 'From sys/audit',
              audit: const [
                FoundAuditVm(
                  time: '03:05',
                  text: 'user:ivan · invoke modbus/tcp-boiler/plc1/valve/~act/edit',
                ),
              ],
            ),
            onTimelineWindow: (_, _) {},
            card: const TaskCardVm(
              title: 'Done',
              note: 'Nothing changed: the assistant only read.',
            ),
            onButton: (_) {},
            newTask: 'New task',
            onNewTask: () {},
            composer: AssistantComposer(
              draft: '',
              hint: 'Ask about what you see… (Cmd+Enter)',
              label: 'Ask',
              onDraft: (_) {},
              onAsk: () {},
              chips: const [
                (
                  'wy/plant/downstream/modbus/tcp-boiler/plc1/valve',
                  'modbus/tcp-boiler/plc1/valve',
                ),
              ],
              addChipLabel: '+ from Explorer',
              dense: true,
            ),
          ),
        ),
      ],
    ),
  );
}

/// *+ from Explorer*: the key picker over the nodes Explorer read, the
/// selection first, with a key typed below the site.
Widget assistantKeyPicker() => Builder(
  builder: (context) => ColoredBox(
    color: const Color(0xFF0E1113),
    child: Align(
      alignment: const Alignment(0, -0.6),
      child: SearchPalette(
        hint: 'Add a node of plant as @ chip: filter, or type its key',
        entries: const [
          SearchEntryVm(
            id: 'wy/plant/downstream/modbus/tcp-boiler/plc1/valve',
            title: 'valve',
            icon: 'node_point',
            detail: 'selected in Explorer',
          ),
          SearchEntryVm(
            id: 'wy/plant/downstream/modbus/tcp-boiler',
            title: 'tcp-boiler',
            icon: 'node_device',
            detail: 'modbus/tcp-boiler',
          ),
          SearchEntryVm(
            id: 'wy/plant/downstream/modbus/tcp-boiler/plc1',
            title: 'Boiler PLC',
            icon: 'node_device',
            detail: 'modbus/tcp-boiler/plc1',
          ),
        ],
        goTo: (_) => null,
        onPick: (_) {},
      ),
    ),
  ),
);
