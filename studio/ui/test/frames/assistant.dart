import 'package:material_ui/material_ui.dart';
import 'package:ui/assistant/conversation.dart';
import 'package:ui/assistant/task_list.dart';
import 'package:ui/buttons/segmented_tabs.dart';
import 'package:ui/containers/fact_grid.dart';
import 'package:ui/indicators/status_pill.dart';
import 'package:ui/models/tone.dart';
import 'package:ui/pages/assistant_page.dart';

/// Board *Assistant* with a task that waits for approval.
Widget assistantPlan() => AssistantPage(
  newLabel: 'New task',
  listNote: 'Each task is a node: agent/tasks/<id>',
  sections: const [
    TaskSectionVm(
      label: 'Now',
      tasks: [
        TaskItemVm(
          id: 't-0142',
          title: 'Add ahu2 on line 2',
          state: 'awaiting approval',
          tone: Tone.warn,
          selected: true,
        ),
      ],
    ),
    TaskSectionVm(
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
  status: const StatusPillVm(label: 'awaiting approval', tone: Tone.warn),
  taskKey: 'tasks/t-0142',
  events: const [
    ConversationEventVm(
      kind: .ask,
      text:
          'Add AHU 2 on line 2. It is unit 3 behind the line-2 gateway, '
          'same points as ahu1. Record its supply temperature every minute.',
    ),
    ConversationEventVm(
      kind: .text,
      text: 'I looked at line 2. ahu1 has 14 points on tcp-line2.',
    ),
    ConversationEventVm(
      kind: .reads,
      reads: ['read · tree', 'read · meta', 'read · get'],
    ),
    ConversationEventVm(
      kind: .text,
      text:
          'Here is the plan: 5 steps, 3 of them change plant. '
          'Nothing runs until you approve.',
    ),
    ConversationEventVm(
      kind: .state,
      text: 'awaiting approval',
      tone: Tone.warn,
    ),
  ],
  card: const TaskCardVm(
    title: 'Plan',
    note:
        "The plan is in the task's record. Studio shows it when the "
        'gateway can read documents.',
    buttons: [
      TaskButtonVm(id: 'reject', label: 'Reject'),
      TaskButtonVm(
        id: 'approve',
        label: 'Approve',
        primary: true,
        disabledReason: 'Approve with wyrm-agent for now.',
      ),
    ],
  ),
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
  facts: const [
    FactVm(label: 'Task', value: 'tasks/t-0142', mono: true),
    FactVm(label: 'State', value: 'awaiting approval'),
    FactVm(label: 'Asked by', value: 'olena'),
    FactVm(label: 'Events', value: '9'),
  ],
  readsLabel: 'What it read',
  reads: const [('tree', ''), ('meta', '× 2'), ('get', '')],
  panelNote:
      'Reading needs no approval. What it reads stays inside your rights '
      'and its own.',
);
