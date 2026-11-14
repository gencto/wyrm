import 'package:material_ui/material_ui.dart';
import 'package:ui/assistant/conversation.dart';
import 'package:ui/assistant/plan_card.dart';
import 'package:ui/assistant/result_card.dart';
import 'package:ui/assistant/run_card.dart';
import 'package:ui/assistant/task_list.dart';
import 'package:ui/buttons/segmented_tabs.dart';
import 'package:ui/containers/fact_grid.dart';
import 'package:ui/indicators/status_pill.dart';
import 'package:ui/models/tone.dart';
import 'package:ui/pages/assistant_page.dart';

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

/// Board *AssistantFailed*: the run stopped at step 2.
Widget assistantFailed() => _assistant(
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
    note: 'stopped · steps 1–1 stay done',
    noteTone: Tone.bad,
  ),
  card: const TaskCardVm(
    title: 'Stopped at step 2',
    note:
        'out_of_range: 21.5 is above max 21\n'
        'What was done before it stays done; nothing is reversed by itself.',
    caution: true,
  ),
);

Widget _assistant({
  required TaskCardVm card,
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
  card: card,
  onButton: (_) {},
  draft: '',
  askHint: 'Ask for a change, or a question about the network (Cmd+Enter)',
  askLabel: 'Ask',
  onDraft: (_) {},
  onAsk: () {},
  panels: const [
    TabItemVm(id: 'task', label: 'This task'),
    TabItemVm(id: 'rights', label: 'What it may do'),
  ],
  panel: 'task',
  onPanel: (_) {},
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
      'The lines after “why” and the warnings come from the model. Read the '
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
