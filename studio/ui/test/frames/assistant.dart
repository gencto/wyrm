import 'package:material_ui/material_ui.dart';
import 'package:ui/assistant/assistant_composer.dart';
import 'package:ui/assistant/assistant_drawer.dart';
import 'package:ui/assistant/blocked.dart';
import 'package:ui/assistant/choices_card.dart';
import 'package:ui/assistant/conversation.dart';
import 'package:ui/assistant/found_card.dart';
import 'package:ui/assistant/more_rows_card.dart';
import 'package:ui/assistant/plan_card.dart';
import 'package:ui/assistant/result_card.dart';
import 'package:ui/assistant/rights_panel.dart';
import 'package:ui/assistant/run_card.dart';
import 'package:ui/assistant/stopped_card.dart';
import 'package:ui/assistant/suggestion_tile.dart';
import 'package:ui/assistant/task_badge.dart';
import 'package:ui/assistant/task_card.dart';
import 'package:ui/assistant/task_list.dart';
import 'package:ui/charts/trend.dart';
import 'package:ui/indicators/app_icon.dart';
import 'package:ui/indicators/level_badge.dart';
import 'package:ui/models/value_changed.dart';
import 'package:ui/overlays/search_palette.dart';
import 'package:ui/pages/assistant_page.dart';

import 'trend.dart' show trendFormat;

const _line2 = 'wy/plant/downstream/modbus/tcp-line2';
const _sp = '$_line2/ahu2/supply_sp';
const _valve = 'wy/plant/downstream/modbus/tcp-boiler/plc1/valve';

/// Board *Assistant* with a task that waits for approval: both changes
/// ticked. With [refusal] the last approval was refused and the task still
/// waits.
Widget assistantPlan({String? refusal}) => _assistant(
  plan: assistantPlanCard(ticks: const [true, true]),
  onTick: (_, {required on}) {},
  card: TaskCardVm(
    badge: .awaitingApproval,
    note: refusal == null
        ? const TaskNoteSigns(role: 'engineer')
        : TaskNoteRefused(refusal),
    buttons: const [
      TaskButtonVm(.reject),
      TaskButtonVm(.approve, count: 2),
    ],
  ),
);

PlanCardVm _folded(TaskBadge badge) => PlanCardVm(
  line: const PlanApproved('approved by olena'),
  badge: badge,
  steps: assistantPlanCard().steps,
  open: false,
);

/// The steps of the plan as the run card lists them.
const _steps = <(StepVerb, String?, String)>[
  (.invoke, 'add_device', _line2),
  (.set, null, _sp),
  (.expect, null, _sp),
];

/// Row [i] of the run: its step, where it stands, its answer; [ended]: the
/// run is over.
RunRowVm _row(
  int i,
  RunStatus status, {
  String answer = '',
  bool ended = false,
}) => RunRowVm(
  n: i + 1,
  verb: _steps[i].$1,
  action: _steps[i].$2,
  node: _steps[i].$3,
  status: status,
  answer: answer,
  ended: ended,
);

/// Board *AssistantRun*: step 2 of the plan runs.
Widget assistantRun() => _assistant(
  badge: .running,
  plan: _folded(.running),
  run: RunCardVm(
    badge: .running,
    step: 2,
    rows: [
      _row(0, .ok, answer: 'added ahu2'),
      _row(1, .running),
      _row(2, .waiting),
    ],
  ),
  card: const TaskCardVm(
    badge: .running,
    note: TaskNoteWorking(),
    buttons: [TaskButtonVm(.cancel)],
  ),
);

/// Board *AssistantDone*: every step passed.
Widget assistantDone() => _assistant(
  badge: .done,
  plan: _folded(.done),
  run: RunCardVm(
    badge: .done,
    seconds: 41,
    rows: [
      _row(0, .ok, answer: 'added ahu2'),
      _row(1, .ok, answer: 'ok'),
      _row(2, .ok, answer: '21.5'),
    ],
  ),
  result: const ResultCardVm(facts: [(key: _sp, value: '21.5 °C')]),
  card: const TaskCardVm(
    badge: .done,
    note: TaskNoteDone(),
    buttons: [
      TaskButtonVm(.explorer, name: _sp),
      TaskButtonVm(.save),
    ],
  ),
);

/// Board *AssistantFailed*: the run stopped at step 2, with the review and
/// the ways out; with [reviewing] the model still reads why.
Widget assistantFailed({bool reviewing = false}) => _assistant(
  badge: .failed,
  plan: _folded(.failed),
  run: RunCardVm(
    badge: .failed,
    kept: const [1],
    rows: [
      _row(0, .ok, answer: 'added ahu2'),
      _row(1, .failed, answer: 'out_of_range: 21.5 is above max 21'),
      _row(2, .waiting, ended: true),
    ],
  ),
  stopped: StoppedCardVm(
    step: 2,
    code: 'out_of_range',
    message: 'out_of_range: 21.5 is above max 21',
    reviewing: reviewing,
    review:
        'The point allows at most 21 °C. ahu1 runs at 21 with the same '
        'setpoint range, so 21 is likely what was meant.',
    ways: reviewing ? const [] : _ways,
    offered: !reviewing,
  ),
  card: reviewing
      ? const TaskCardVm(
          badge: .failed,
          note: TaskNoteWorking(),
          buttons: [TaskButtonVm(.cancel)],
        )
      : null,
  hint: .failed,
  hintNode: _sp,
);

const _ways = [
  SuggestionTileVm(
    id: 's1',
    label: 'Set 21 instead',
    detail: 'A new plan with one step: set supply_sp to 21, then the check.',
    changes: 1,
  ),
  SuggestionTileVm(
    id: 's2',
    label: 'Undo the plan',
    detail: 'A plan that removes ahu2 (step 1, reversed).',
    changes: 1,
  ),
  SuggestionTileVm(
    id: 's3',
    label: 'Leave it as it is',
    detail: 'ahu2 stays with its default setpoint.',
    changes: 0,
  ),
];

/// Board *Assistant*, a step with the link's warning, the model's words and
/// a fix that replaces the plan; the composer holds an `@` chip.
Widget assistantFix() {
  final plan = assistantPlanCard(ticks: const [true, true]);
  return _assistant(
    plan: PlanCardVm(
      line: plan.line,
      badge: plan.badge,
      steps: [
        const PlanStepVm(
          n: 1,
          verb: .invoke,
          action: 'add_device',
          node: _line2,
          level: AccessLevel.config,
          args: [
            StepArgVm.shown('name', 'ahu2'),
            StepArgVm.shown('slave_id', '3'),
            StepArgVm.shown('poll_s', '5'),
          ],
          check: .now,
          warn: 'unit 3 answers with exception 0x0B behind this gateway',
          modelWarn:
              'ahu-old answered on unit 3 until March; the new box is '
              'likely unit 4.',
          fixes: [
            SuggestionTileVm(
              id: 'f1',
              label: 'Try Slave ID 4',
              detail: 'The same plan with slave_id 4.',
              changes: 1,
              note: .fix,
            ),
          ],
          why: 'the unit the operator named, with the points of ahu1',
          ticked: true,
        ),
        ...plan.steps.skip(1),
      ],
    ),
    onTick: (_, {required on}) {},
    card: const TaskCardVm(
      badge: .awaitingApproval,
      note: TaskNoteSigns(role: 'engineer'),
      buttons: [
        TaskButtonVm(.reject),
        TaskButtonVm(.approve, count: 2),
      ],
    ),
    chips: const [_line2],
    hint: .awaiting,
    replaces: true,
  );
}

/// Board *AssistantDone* with *Same for more units?*: one row ticked.
Widget assistantMore() => _assistant(
  badge: .done,
  plan: _folded(.done),
  result: const ResultCardVm(facts: [(key: _sp, value: '21.5 °C')]),
  more: const [
    MoreRowsCardVm(
      id: 's1',
      title: 'Same for more units?',
      detail: 'ahu3 and ahu4 answer on line 2 with the points of ahu1.',
      rows: [
        MoreRowVm(
          key: '$_line2/ahu3',
          label: 'ahu3',
          detail: 'unit 5 · 14 points',
          ticked: true,
        ),
        MoreRowVm(
          key: '$_line2/ahu4',
          label: 'ahu4',
          detail: 'unit 6 · 14 points',
        ),
      ],
    ),
  ],
  card: const TaskCardVm(
    badge: .done,
    note: TaskNoteDone(),
    buttons: [
      TaskButtonVm(.explorer, name: _sp),
      TaskButtonVm(.save),
    ],
  ),
  hint: .done,
);

/// A plan another task replaced: no ticks, no Approve, the way on.
Widget assistantReplaced() => _assistant(
  badge: .failed,
  plan: PlanCardVm(
    line: const PlanReplaced('t-0143'),
    badge: .failed,
    steps: assistantPlanCard().steps,
    open: false,
  ),
  card: const TaskCardVm(
    badge: .failed,
    note: TaskNoteReplaced('t-0143'),
    buttons: [TaskButtonVm(.replacement, name: 't-0143')],
  ),
  replacedBy: 't-0143',
);

/// Board *AssistantAsk*: the assistant asks back; one option is picked.
Widget assistantAsk() => _assistant(
  badge: .awaitingAnswer,
  choices: const ChoicesCardVm(
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
    confirm: true,
  ),
  card: const TaskCardVm(
    badge: .awaitingAnswer,
    note: TaskNoteAnswer(),
    buttons: [TaskButtonVm(.cancel)],
  ),
);

Widget _assistant({
  TaskCardVm? card,
  StoppedCardVm? stopped,
  List<MoreRowsCardVm> more = const [],
  List<String> chips = const [],
  ComposerHint hint = .ask,
  String hintNode = '',
  bool replaces = false,
  String? replacedBy,
  RightsPanelVm? rights,
  ChoicesCardVm? choices,
  TaskBadge badge = .awaitingApproval,
  PlanCardVm? plan,
  Toggled<int>? onTick,
  RunCardVm? run,
  ResultCardVm? result,
}) => AssistantPage(
  sections: [
    TaskSectionVm(
      section: .now,
      tasks: [
        TaskItemVm(
          id: 't-0142',
          title: 'Add ahu2 on line 2',
          badge: badge,
          replacedBy: replacedBy,
          selected: true,
        ),
      ],
    ),
    const TaskSectionVm(
      section: .earlier,
      tasks: [
        TaskItemVm(
          id: 't-0141',
          title: 'Why is boiler valve bad?',
          badge: .done,
        ),
        TaskItemVm(
          id: 't-0131',
          title: 'Rename the S7 points of press 2',
          badge: .failed,
        ),
      ],
    ),
  ],
  onNew: () {},
  onTask: (_) {},
  title: 'Add ahu2 on line 2',
  badge: badge,
  taskId: 't-0142',
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
    ConversationEventVm.read('tree'),
    ConversationEventVm.read('meta'),
    ConversationEventVm.read('get'),
    const ConversationEventVm(
      kind: .text,
      text:
          'Here is the plan: 5 steps, 3 of them change plant. '
          'Nothing runs until you approve.',
    ),
    ConversationEventVm(kind: .state, badge: badge),
  ],
  plan: plan,
  onTick: onTick,
  run: run,
  result: result,
  more: more,
  onRow: (_, {required on}) {},
  onMore: (_) {},
  stopped: stopped,
  onWay: (_) {},
  onFix: (_) {},
  choices: choices,
  onPick: (_, _) {},
  onAnswer: () {},
  card: card,
  onButton: (_) {},
  composer: ComposerVm(
    draft: '',
    hint: hint,
    node: hintNode,
    chips: chips,
    // the box's own tooltip is not drawn: only that it is disabled
    chipBlocked: chips.isEmpty ? const BlockedNoSite() : null,
    replaces: replaces,
  ),
  onChipRemove: (_) {},
  onAddChip: () {},
  onDraft: (_) {},
  onAsk: () {},
  panel: rights == null ? .task : .rights,
  onPanel: (_) {},
  rights: rights,
  onMode: (_) {},
  onRemovePrefix: (_) {},
  onAddPrefix: () {},
  facts: TaskFactsVm(
    taskId: 't-0142',
    badge: badge,
    owner: 'olena',
    events: 9,
  ),
  reads: const [('tree', 1), ('meta', 2), ('get', 1)],
);

/// The plan of [assistantPlan]: a config step, a step checked when it runs
/// with a warning, and a proof. [ticks] gives the changing steps a tick.
PlanCardVm assistantPlanCard({List<bool>? ticks}) => PlanCardVm(
  line: const PlanChecked(now: 1, atRun: 1),
  badge: .awaitingApproval,
  steps: [
    PlanStepVm(
      n: 1,
      verb: .invoke,
      action: 'add_device',
      node: _line2,
      level: AccessLevel.config,
      args: const [
        StepArgVm.shown('name', 'ahu2'),
        StepArgVm.shown('slave_id', '3'),
        StepArgVm.shown('poll_s', '5'),
      ],
      check: .now,
      why: 'the unit the operator named, with the points of ahu1',
      ticked: ticks?[0],
    ),
    PlanStepVm(
      n: 2,
      verb: .set,
      node: _sp,
      level: AccessLevel.write,
      args: const [StepArgVm.shown('value', '21.5')],
      check: .atRun,
      warn: "the value 21.5 is at the point's max (21.5)",
      note: const StepAfter([1]),
      ticked: ticks?[1],
    ),
    const PlanStepVm(
      n: 3,
      verb: .expect,
      node: _sp,
      level: AccessLevel.read,
      args: [StepArgVm.shown('equals', '21.5'), StepArgVm.timeout(10)],
      note: StepAfter([2]),
    ),
  ],
);

/// Board *AssistantRights*: what the agent may do; a mode change is staged.
Widget assistantRights() => _assistant(
  plan: assistantPlanCard(ticks: const [true, true]),
  onTick: (_, {required on}) {},
  card: const TaskCardVm(
    badge: .awaitingApproval,
    note: TaskNoteSigns(role: 'engineer'),
  ),
  rights: const RightsPanelVm(
    modes: [
      ModeVm(.write, selected: true),
      ModeVm(.config),
      ModeVm(.never),
    ],
    prefixes: [
      'wy/plant/downstream/modbus',
      'wy/plant/sys/history',
      'wy/plant/dataflows',
    ],
    agent: 'agent',
    model: 'claude-sonnet-5-5',
    used: 182000,
    budget: 1000000,
    apiKeyRef: 'anthropic_api_key',
    apiKey: .set,
    sentTo: 'api.anthropic.com',
    staged: true,
  ),
);

/// The drawer's conversation about the valve.
final _drawerEvents = [
  const ConversationEventVm(kind: .ask, text: 'Why is the valve bad?'),
  const ConversationEventVm(
    kind: .text,
    text:
        'The connection and plc1 are fine; only valve fails. Its '
        'offset was changed 7 minutes before it went bad.',
  ),
  ConversationEventVm.read('tree'),
  ConversationEventVm.read('get'),
  ConversationEventVm.read('audit'),
];

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
          taskId: 't-0141',
          onOpenFull: () {},
          onClose: () {},
          events: _drawerEvents,
          plan: const PlanCardVm(
            line: PlanChecked(now: 1, atRun: 0),
            badge: .awaitingApproval,
            steps: [
              PlanStepVm(
                n: 1,
                verb: .invoke,
                action: 'edit',
                node: _valve,
                level: AccessLevel.config,
                args: [StepArgVm.shown('offset', '11')],
                check: .now,
                why: 'it read well at 11 until the edit',
                ticked: true,
              ),
            ],
          ),
          onTick: (_, {required on}) {},
          card: const TaskCardVm(
            badge: .awaitingApproval,
            note: TaskNoteSigns(role: 'engineer'),
            buttons: [
              TaskButtonVm(.reject),
              TaskButtonVm(.approve, count: 1),
            ],
          ),
          onButton: (_) {},
          second: const SuggestionTileVm(
            id: 's1',
            label: 'Ask ivan first',
            detail: 'Ivan, did you move valve to offset 12 at 03:05?',
            changes: 0,
            note: .draft,
          ),
          onSecond: () async {},
          onNewTask: () {},
          composer: AssistantComposer(
            vm: const ComposerVm(
              draft: '',
              hint: .drawer,
              chips: [_valve],
              dense: true,
            ),
            onDraft: (_) {},
            onAsk: () {},
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
            taskId: 't-0141',
            onOpenFull: () {},
            onClose: () {},
            events: _drawerEvents,
            found: FoundCardVm(
              rows: const [
                FoundRowVm(
                  label: 'tcp-boiler',
                  detail: 'connected · 10.0.4.12:502',
                  node: 'wy/plant/downstream/modbus/tcp-boiler',
                  mark: .none,
                ),
                FoundRowVm(
                  label: 'plc1',
                  detail: '4 of 5 points good',
                  node: 'wy/plant/downstream/modbus/tcp-boiler/plc1',
                  mark: .good,
                ),
                FoundRowVm(
                  label: 'valve',
                  detail:
                      'bad since 03:12 · exception 0x02 illegal data address',
                  node: _valve,
                  mark: .bad,
                ),
              ],
              point: 'valve',
              range: '1h',
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
                format: trendFormat,
              ),
              audit: [
                FoundAuditVm(
                  time: DateTime.fromMicrosecondsSinceEpoch(edit, isUtc: true),
                  who: 'user:ivan',
                  op: 'invoke',
                  key: '$_valve/~act/edit',
                ),
              ],
            ),
            onTimelineWindow: (_, _) {},
            card: const TaskCardVm(badge: .done, note: TaskNoteDone()),
            onButton: (_) {},
            onNewTask: () {},
            composer: AssistantComposer(
              vm: const ComposerVm(
                draft: '',
                hint: .drawer,
                chips: [_valve],
                dense: true,
              ),
              onDraft: (_) {},
              onAsk: () {},
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
            icon: AppIcon.nodePoint,
            detail: 'selected in Explorer',
          ),
          SearchEntryVm(
            id: 'wy/plant/downstream/modbus/tcp-boiler',
            title: 'tcp-boiler',
            icon: AppIcon.nodeDevice,
            detail: 'modbus/tcp-boiler',
          ),
          SearchEntryVm(
            id: 'wy/plant/downstream/modbus/tcp-boiler/plc1',
            title: 'Boiler PLC',
            icon: AppIcon.nodeDevice,
            detail: 'modbus/tcp-boiler/plc1',
          ),
        ],
        goTo: (_) => null,
      ),
    ),
  ),
);
