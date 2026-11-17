import 'package:equatable/equatable.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';

import '../assistant/assistant_composer.dart';
import '../assistant/blocked.dart';
import '../assistant/choices_card.dart';
import '../assistant/conversation.dart';
import '../assistant/more_rows_card.dart';
import '../assistant/plan_card.dart';
import '../assistant/result_card.dart';
import '../assistant/rights_panel.dart';
import '../assistant/run_card.dart';
import '../assistant/stopped_card.dart';
import '../assistant/task_badge.dart';
import '../assistant/task_card.dart';
import '../assistant/task_list.dart';
import '../buttons/button.dart';
import '../buttons/segmented_tabs.dart';
import '../containers/fact_grid.dart';
import '../containers/section_label.dart';
import '../indicators/app_icon.dart';
import '../indicators/status_pill.dart';
import '../models/value_changed.dart';
import '../theme/extensions/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';

export '../assistant/task_card.dart' show TaskButton, TaskButtonVm, TaskCardVm;

/// One tool of WHAT IT READ and how many times the model called it.
typedef ReadRow = (String tool, int times);

/// A row of *Same for more units?*: the suggestion it belongs to and the
/// node's key.
typedef MoreRowRef = ({String suggestion, String key});

/// The panels on the right of the Assistant.
enum AssistantTab {
  task,
  rights;

  String get label => switch (this) {
    task => S.current.panelThisTask,
    rights => S.current.panelMayDo,
  };
}

/// *This task*: the selected task's facts.
final class TaskFactsVm extends Equatable {
  const TaskFactsVm({
    required this.taskId,
    required this.badge,
    this.owner = '',
    this.events = 0,
  });

  final String taskId;
  final TaskBadge badge;

  /// Who asked (`user:olena`); empty when not known.
  final String owner;

  /// How many lines its conversation holds in this session.
  final int events;

  List<FactVm> get facts => [
    FactVm(label: S.current.factTask, value: 'tasks/$taskId', mono: true),
    FactVm(label: S.current.factTaskState, value: badge.label),
    if (owner.isNotEmpty) FactVm(label: S.current.factAskedBy, value: owner),
    if (events > 0) FactVm(label: S.current.factEvents, value: '$events'),
  ];

  @override
  List<Object?> get props => [taskId, badge, owner, events];
}

/// Board *Assistant*: tasks on the left, the selected task's conversation
/// with its card and the ask box in the middle, *This task* and *What it
/// may do* on the right. With [noAgent] (no agent link on the site) the
/// middle says so and offers to add one.
class AssistantPage extends StatelessWidget {
  const AssistantPage({
    required this.sections,
    required this.onNew,
    required this.onTask,
    required this.events,
    required this.composer,
    required this.onDraft,
    required this.onAsk,
    required this.panel,
    required this.onPanel,
    required this.reads,
    required this.onButton,
    this.agent,
    this.noAgent = false,
    this.title,
    this.badge,
    this.taskId,
    this.plan,
    this.onTick,
    this.onFix,
    this.onReveal,
    this.run,
    this.result,
    this.more = const [],
    this.onRow,
    this.onMore,
    this.stopped,
    this.onWay,
    this.choices,
    this.onPick,
    this.onAnswer,
    this.card,
    this.onChipRemove,
    this.onAddChip,
    this.facts,
    this.rights,
    this.onMode,
    this.onRemovePrefix,
    this.onAddPrefix,
    this.onAddAgent,
    super.key,
  });

  final List<TaskSectionVm> sections;
  final VoidCallback onNew;
  final ValueChanged<String> onTask;

  /// The agent link's key; null when the site has none.
  final String? agent;

  /// The site has no agent link.
  final bool noAgent;

  /// The selected task's ask.
  final String? title;
  final TaskBadge? badge;

  /// The selected task (`t-0142`).
  final String? taskId;
  final List<ConversationEventVm> events;

  /// The task's plan, above its card; null while it is not known.
  final PlanCardVm? plan;

  /// A step of [plan] was ticked; null: the plan is only shown.
  final Toggled<int>? onTick;

  /// A fix of a step (a suggestion id) was picked.
  final ValueChanged<String>? onFix;

  /// The masked arguments of a step (by number) are shown or masked again.
  final ValueChanged<int>? onReveal;

  /// The run of the plan, under it; null before a run.
  final RunCardVm? run;

  /// What a finished plan left behind.
  final ResultCardVm? result;

  /// *Same for more units?*: the suggestions with rows, under [result].
  final List<MoreRowsCardVm> more;
  final Toggled<MoreRowRef>? onRow;
  final ValueChanged<String>? onMore;

  /// Where a run stopped and the ways out.
  final StoppedCardVm? stopped;
  final ValueChanged<String>? onWay;

  /// What the assistant asked the person, answered or not.
  final ChoicesCardVm? choices;
  final OptionPicked? onPick;

  /// The picks of [choices] are sent (`Write the plan`).
  final VoidCallback? onAnswer;
  final TaskCardVm? card;
  final ValueChanged<TaskButtonVm> onButton;

  /// The ask box.
  final ComposerVm composer;
  final ValueChanged<String>? onChipRemove;
  final VoidCallback? onAddChip;
  final ValueChanged<String> onDraft;
  final VoidCallback onAsk;

  final AssistantTab panel;
  final ValueChanged<AssistantTab> onPanel;

  /// *This task*; null when no task is selected.
  final TaskFactsVm? facts;

  /// WHAT IT READ in this session; empty under *What it may do*.
  final List<ReadRow> reads;

  /// *What it may do*: shown in place of [facts] and [reads].
  final RightsPanelVm? rights;
  final ValueChanged<AgentModeVm>? onMode;
  final ValueChanged<String>? onRemovePrefix;
  final VoidCallback? onAddPrefix;

  /// *Add the agent link*, when the site has none.
  final VoidCallback? onAddAgent;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final left = Container(
      width: 240,
      decoration: BoxDecoration(
        color: c.ground1,
        border: Border(right: BorderSide(color: c.line1)),
      ),
      child: TaskList(
        sections: sections,
        onNew: onNew,
        onTask: onTask,
        agent: agent,
        noAgent: noAgent,
      ),
    );
    final Widget middle;
    if (noAgent) {
      middle = Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: .min,
            spacing: 16,
            children: [
              Text(
                const BlockedNoAgent().text,
                textAlign: .center,
                style: TextStyle(
                  fontSize: FontSizes.lg,
                  height: LineHeights.body,
                  color: c.text2,
                ),
              ),
              Button.primary(
                label: S.current.addAgent,
                icon: AppIcon.uiAdd,
                onPressed: onAddAgent,
              ),
            ],
          ),
        ),
      );
    } else {
      middle = Column(
        crossAxisAlignment: .stretch,
        children: [
          Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: c.line1)),
            ),
            child: Row(
              spacing: 12,
              children: [
                Expanded(
                  child: Text(
                    title ?? '',
                    overflow: .ellipsis,
                    style: TextStyle(
                      fontSize: FontSizes.conversationTitle,
                      fontWeight: .w600,
                      color: c.text1,
                    ),
                  ),
                ),
                if (badge case final b?)
                  StatusPill(
                    vm: StatusPillVm(label: b.label, tone: b.tone),
                    dense: true,
                  ),
                if (taskId case final id?)
                  Text(
                    'tasks/$id',
                    style: mono(size: FontSizes.sm, color: c.text3),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Conversation(
              events: events,
              trailing:
                  plan == null &&
                      card == null &&
                      choices == null &&
                      stopped == null
                  ? null
                  : Column(
                      crossAxisAlignment: .stretch,
                      children: [
                        if (choices case final q?)
                          ChoicesCard(
                            vm: q,
                            onPick: onPick ?? (_, _) {},
                            onConfirm: onAnswer ?? () {},
                          ),
                        if (plan case final p?)
                          PlanCard(
                            vm: p,
                            onTick: onTick,
                            onFix: onFix,
                            onReveal: onReveal,
                          ),
                        if (run case final r?) RunCard(vm: r),
                        if (result case final r?) ResultCard(vm: r),
                        for (final m in more)
                          MoreRowsCard(
                            vm: m,
                            onRow: (key, {required on}) => onRow?.call((
                              suggestion: m.id,
                              key: key,
                            ), on: on),
                            onAsk: () => onMore?.call(m.id),
                          ),
                        if (stopped case final st?)
                          StoppedCard(vm: st, onPick: onWay),
                        if (card case final k?)
                          TaskCard(vm: k, onButton: onButton),
                      ],
                    ),
            ),
          ),
          AssistantComposer(
            vm: composer,
            onDraft: onDraft,
            onAsk: onAsk,
            onChipRemove: onChipRemove,
            onAddChip: onAddChip,
          ),
        ],
      );
    }
    final right = Container(
      width: 300,
      decoration: BoxDecoration(
        color: c.ground1,
        border: Border(left: BorderSide(color: c.line1)),
      ),
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          SegmentedTabs(
            tabs: [
              for (final t in AssistantTab.values)
                TabItemVm(id: t.name, label: t.label),
            ],
            selected: panel.name,
            onSelect: (id) => onPanel(AssistantTab.values.byName(id)),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(18),
              children: [
                if (rights case final r?)
                  RightsPanel(
                    vm: r,
                    onMode: onMode,
                    onRemovePrefix: onRemovePrefix,
                    onAddPrefix: onAddPrefix,
                  )
                else
                  FactGrid(facts: facts?.facts ?? const [], labelWidth: 96),
                if (reads.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  SectionLabel(S.current.whatItRead),
                  Gaps.sm,
                  for (final (tool, times) in reads)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: .start,
                        spacing: 8,
                        children: [
                          Text(
                            tool,
                            style: mono(size: FontSizes.sm, color: c.good),
                          ),
                          Expanded(
                            child: Text(
                              times > 1 ? '× $times' : '',
                              style: mono(size: FontSizes.sm, color: c.text2),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
                if (reads.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(
                    S.current.readsNote,
                    style: TextStyle(
                      fontSize: FontSizes.sm,
                      height: LineHeights.body,
                      color: c.text3,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
    return ColoredBox(
      color: c.ground0,
      child: Row(
        crossAxisAlignment: .stretch,
        children: [
          left,
          Expanded(child: middle),
          right,
        ],
      ),
    );
  }
}
