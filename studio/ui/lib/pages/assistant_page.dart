import 'package:material_ui/material_ui.dart';

import '../assistant/assistant_composer.dart';
import '../assistant/choices_card.dart';
import '../assistant/conversation.dart';
import '../assistant/more_rows_card.dart';
import '../assistant/plan_card.dart';
import '../assistant/result_card.dart';
import '../assistant/rights_panel.dart';
import '../assistant/run_card.dart';
import '../assistant/stopped_card.dart';
import '../assistant/task_card.dart';
import '../assistant/task_list.dart';
import '../buttons/button.dart';
import '../buttons/segmented_tabs.dart';
import '../containers/fact_grid.dart';
import '../containers/section_label.dart';
import '../indicators/status_pill.dart';
import '../theme/extensions/colors.dart';
import '../theme/typography.dart';

export '../assistant/assistant_composer.dart' show ChipVm;
export '../assistant/task_card.dart' show TaskButtonVm, TaskCardVm;

/// One `kind  key` row of WHAT IT READ.
typedef ReadRow = (String kind, String key);

/// Board *Assistant*: tasks on the left, the selected task's conversation
/// with its card and the ask box in the middle, *This task* and *What it
/// may do* on the right. With [empty] set (no agent link on the site) the
/// middle shows it and [emptyAction] instead.
class AssistantPage extends StatelessWidget {
  const AssistantPage({
    required this.newLabel,
    required this.listNote,
    required this.sections,
    required this.onNew,
    required this.onTask,
    required this.events,
    required this.draft,
    required this.askHint,
    required this.askLabel,
    required this.onDraft,
    required this.onAsk,
    required this.panels,
    required this.panel,
    required this.onPanel,
    required this.facts,
    required this.readsLabel,
    required this.reads,
    required this.panelNote,
    required this.onButton,
    this.title,
    this.status,
    this.taskKey,
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
    this.askReason,
    this.chips = const [],
    this.onChipRemove,
    this.addChipLabel,
    this.addChipReason,
    this.onAddChip,
    this.rights,
    this.onMode,
    this.onRemovePrefix,
    this.onAddPrefix,
    this.empty,
    this.emptyAction,
    this.onEmptyAction,
    super.key,
  });

  final String newLabel;
  final String listNote;
  final List<TaskSectionVm> sections;
  final VoidCallback onNew;
  final ValueChanged<String> onTask;

  final String? title;
  final StatusPillVm? status;

  /// `tasks/t-0142`.
  final String? taskKey;
  final List<ConversationEventVm> events;

  /// The task's plan, above its card; null while it is not known.
  final PlanCardVm? plan;

  /// A step of [plan] was ticked; null: the plan is only shown.
  final void Function(int n, {required bool ticked})? onTick;

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
  final void Function(String suggestion, String key, {required bool on})? onRow;
  final ValueChanged<String>? onMore;

  /// Where a run stopped and the ways out.
  final StoppedCardVm? stopped;
  final ValueChanged<String>? onWay;

  /// What the assistant asked the person, answered or not.
  final ChoicesCardVm? choices;
  final void Function(String question, String option)? onPick;

  /// The picks of [choices] are sent (`Write the plan`).
  final VoidCallback? onAnswer;
  final TaskCardVm? card;
  final ValueChanged<String> onButton;

  final String draft;
  final String askHint;
  final String askLabel;

  /// Why asking is not possible (no write on the agent, no agent).
  final String? askReason;

  /// The `@` chips that go with the ask as its context.
  final List<ChipVm> chips;
  final ValueChanged<String>? onChipRemove;

  /// `+ from Explorer`; null: not offered.
  final String? addChipLabel;
  final String? addChipReason;
  final VoidCallback? onAddChip;
  final ValueChanged<String> onDraft;
  final VoidCallback onAsk;

  final List<TabItemVm> panels;
  final String panel;
  final ValueChanged<String> onPanel;
  final List<FactVm> facts;
  final String readsLabel;
  final List<ReadRow> reads;
  final String panelNote;

  /// *What it may do*: shown in place of [facts] and [reads].
  final RightsPanelVm? rights;
  final ValueChanged<String>? onMode;
  final ValueChanged<String>? onRemovePrefix;
  final VoidCallback? onAddPrefix;

  final String? empty;
  final String? emptyAction;
  final VoidCallback? onEmptyAction;

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
        newLabel: newLabel,
        note: listNote,
        sections: sections,
        onNew: onNew,
        onTask: onTask,
        newReason: empty,
      ),
    );
    final Widget middle;
    if (empty case final e?) {
      middle = Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: .min,
            spacing: 16,
            children: [
              Text(
                e,
                textAlign: .center,
                style: TextStyle(fontSize: 14, height: 1.5, color: c.text2),
              ),
              if (emptyAction case final a?)
                Button.primary(
                  label: a,
                  icon: 'ui_add',
                  onPressed: onEmptyAction,
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
            padding: const EdgeInsets.symmetric(horizontal: 24),
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
                      fontSize: 17,
                      fontWeight: .w600,
                      color: c.text1,
                    ),
                  ),
                ),
                if (status case final s?) StatusPill(vm: s, dense: true),
                if (taskKey case final k?)
                  Text(k, style: mono(size: 12, color: c.text3)),
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
                            onRow: (key, {required on}) =>
                                onRow?.call(m.id, key, on: on),
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
            draft: draft,
            hint: askHint,
            label: askLabel,
            reason: askReason,
            onDraft: onDraft,
            onAsk: onAsk,
            chips: chips,
            onChipRemove: onChipRemove,
            addChipLabel: addChipLabel,
            addChipReason: addChipReason,
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
          SegmentedTabs(tabs: panels, selected: panel, onSelect: onPanel),
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
                  FactGrid(facts: facts, labelWidth: 96),
                if (reads.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  SectionLabel(readsLabel),
                  const SizedBox(height: 8),
                  for (final (kind, key) in reads)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: .start,
                        spacing: 8,
                        children: [
                          Text(kind, style: mono(size: 12, color: c.good)),
                          Expanded(
                            child: Text(
                              key,
                              style: mono(size: 12, color: c.text2),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
                if (panelNote.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(
                    panelNote,
                    style: TextStyle(fontSize: 12, height: 1.5, color: c.text3),
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
