import 'package:material_ui/material_ui.dart';

import '../indicators/app_icon.dart';
import '../theme/extensions/colors.dart';
import '../theme/typography.dart';
import 'assistant_composer.dart';
import 'choices_card.dart';
import 'conversation.dart';
import 'found_card.dart';
import 'plan_card.dart';
import 'run_card.dart';
import 'stopped_card.dart';
import 'suggestion_tile.dart';
import 'task_card.dart';

/// Board *AssistantDrawer*: the Assistant over Explorer (⌘J), 420 wide, about
/// the selection. The same cards as the Assistant tab, one column; the
/// header names the task, *Open full* goes to the tab with the same task.
class AssistantDrawer extends StatelessWidget {
  const AssistantDrawer({
    required this.title,
    required this.openFull,
    required this.closeLabel,
    required this.onOpenFull,
    required this.onClose,
    required this.events,
    required this.composer,
    required this.onButton,
    this.taskKey,
    this.choices,
    this.onPick,
    this.onAnswer,
    this.plan,
    this.onTick,
    this.onFix,
    this.onReveal,
    this.run,
    this.stopped,
    this.onWay,
    this.card,
    this.secondLabel,
    this.second,
    this.onSecond,
    this.newTask,
    this.onNewTask,
    this.empty,
    this.found,
    this.onTimelineWindow,
    this.onTimelineReset,
    super.key,
  });

  /// `Assistant`.
  final String title;

  /// `tasks/t-0141`; null before a task.
  final String? taskKey;
  final String openFull;
  final String closeLabel;

  /// Null: there is no task to open.
  final VoidCallback? onOpenFull;
  final VoidCallback onClose;

  final List<ConversationEventVm> events;
  final ChoicesCardVm? choices;
  final void Function(String question, String option)? onPick;
  final VoidCallback? onAnswer;
  final PlanCardVm? plan;
  final void Function(int n, {required bool ticked})? onTick;
  final ValueChanged<String>? onFix;
  final ValueChanged<int>? onReveal;
  final RunCardVm? run;
  final StoppedCardVm? stopped;
  final ValueChanged<String>? onWay;

  /// The task's card with Approve and run, and the second button the
  /// model may offer.
  final TaskCardVm? card;
  final ValueChanged<String> onButton;

  /// `The assistant suggests`: above [second].
  final String? secondLabel;

  /// The second button the model may offer (spec §5), as the model's
  /// tile: its words, the guessed changes, what a pick does.
  final SuggestionTileVm? second;
  final VoidCallback? onSecond;

  /// `New task`: a question in the drawer then starts a task of its own.
  final String? newTask;
  final VoidCallback? onNewTask;

  /// The ask box, in the drawer's density.
  final AssistantComposer composer;

  /// Why there is nothing to ask (no agent link).
  final String? empty;

  /// *What I found* and the mini timeline of the selected point; null when
  /// there is neither.
  final FoundCardVm? found;
  final void Function(int start, int end)? onTimelineWindow;
  final VoidCallback? onTimelineReset;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.ground1,
      elevation: 12,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: c.line2)),
        ),
        child: Column(
          crossAxisAlignment: .stretch,
          children: [
            Container(
              height: 48,
              padding: const EdgeInsets.only(left: 16, right: 6),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: c.line1)),
              ),
              child: Row(
                spacing: 8,
                children: [
                  AppIcon('ws_assistant', size: 15, color: c.ember),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: .w600,
                      color: c.text1,
                    ),
                  ),
                  if (taskKey case final k?)
                    Flexible(
                      child: Text(
                        k,
                        overflow: .ellipsis,
                        style: mono(size: 12, color: c.text3),
                      ),
                    ),
                  const Spacer(),
                  if (newTask case final n? when onNewTask != null)
                    TextButton(onPressed: onNewTask, child: Text(n)),
                  if (onOpenFull != null)
                    TextButton(onPressed: onOpenFull, child: Text(openFull)),
                  IconButton(
                    tooltip: closeLabel,
                    onPressed: onClose,
                    icon: AppIcon('ui_close', size: 14, color: c.text2),
                  ),
                ],
              ),
            ),
            Expanded(
              child: empty != null
                  ? Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        empty!,
                        style: TextStyle(fontSize: 13, color: c.text2),
                      ),
                    )
                  : Conversation(
                      events: events,
                      dense: true,
                      trailing: Column(
                        crossAxisAlignment: .stretch,
                        children: [
                          if (found case final f?)
                            FoundCard(
                              vm: f,
                              onWindow: onTimelineWindow ?? (_, _) {},
                              onReset: onTimelineReset,
                            ),
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
                          if (stopped case final st?)
                            StoppedCard(vm: st, onPick: onWay),
                          if (card case final k?)
                            TaskCard(vm: k, onButton: onButton),
                          if (second case final t?)
                            Padding(
                              padding: const EdgeInsets.only(left: 42, top: 12),
                              child: Column(
                                crossAxisAlignment: .stretch,
                                spacing: 6,
                                children: [
                                  if (secondLabel case final l?)
                                    Text(
                                      l,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: c.text3,
                                      ),
                                    ),
                                  SuggestionTile(vm: t, onTap: onSecond),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
            ),
            composer,
          ],
        ),
      ),
    );
  }
}
