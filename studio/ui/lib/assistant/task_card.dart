import 'package:equatable/equatable.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';

import '../buttons/button.dart';
import '../containers/section_label.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';
import 'blocked.dart';
import 'task_badge.dart';

/// A button under the selected task.
enum TaskButton {
  cancel,
  reject,
  approve,

  /// Opens the task that replaced this one.
  replacement,

  /// Opens the node the plan changed in Explorer.
  explorer,

  /// Opens the trend of the point the plan touched last.
  trend,

  /// Saves the plan as a `wyrm-agent run` file.
  save,

  /// Asks for the steps a run left out.
  followUp,
}

/// A button under the selected task (Approve, Reject, Cancel).
final class TaskButtonVm extends Equatable {
  const TaskButtonVm(
    this.button, {
    this.name = '',
    this.count = 0,
    this.steps = const [],
    this.blocked,
  });

  final TaskButton button;

  /// The node, the point or the task it names.
  final String name;

  /// Follow-up: the steps the run left out.
  final List<int> steps;

  /// Approve: how many changes run once approved; 0 when none is ticked.
  final int count;

  /// Why it cannot be pressed; null: it can.
  final Blocked? blocked;

  String get label => switch (button) {
    TaskButton.cancel => S.current.cancelTask,
    TaskButton.reject => S.current.reject,
    TaskButton.approve =>
      count == 0 ? S.current.approve : S.current.approveCount(count),
    TaskButton.replacement => S.current.openReplacement(name),
    TaskButton.explorer => S.current.openNodeInExplorer(lastSegment(name)),
    TaskButton.trend => S.current.trendPoint(lastSegment(name)),
    TaskButton.save => S.current.saveAsPlan,
    TaskButton.followUp => S.current.followUpLeftOut,
  };

  bool get primary => switch (button) {
    TaskButton.approve || TaskButton.replacement || TaskButton.followUp => true,
    _ => false,
  };

  bool get danger => button == TaskButton.cancel;

  String? get disabledReason => blocked?.text;

  /// Follow-up: what the person asks the agent, in their words.
  String get says => S.current.followUpAsk(name, steps.join(', '));

  @override
  List<Object?> get props => [button, name, count, steps, blocked];
}

/// What the card under a task says.
sealed class TaskNoteVm extends Equatable {
  const TaskNoteVm();

  String get text;

  /// It is said on the warning band.
  bool get caution => false;

  @override
  List<Object?> get props => [];
}

/// Another task took this one's place.
final class TaskNoteReplaced extends TaskNoteVm {
  const TaskNoteReplaced(this.by);

  final String by;

  @override
  String get text => S.current.replacedNote(by);

  @override
  List<Object?> get props => [by];
}

/// The gateway cannot read the plan (older than `doc`).
final class TaskNoteNoRecord extends TaskNoteVm {
  const TaskNoteNoRecord();

  @override
  String get text => S.current.planNote;

  @override
  bool get caution => true;
}

/// The task is on another site: this gateway does not sign for it.
final class TaskNoteOtherSite extends TaskNoteVm {
  const TaskNoteOtherSite(this.site);

  final String site;

  @override
  String get text => S.current.approveOtherSite(site);

  @override
  bool get caution => true;

  @override
  List<Object?> get props => [site];
}

/// The approval was refused; the task still waits.
final class TaskNoteRefused extends TaskNoteVm {
  const TaskNoteRefused(this.why);

  /// What the gateway or the link said.
  final String why;

  @override
  String get text =>
      '${S.current.approveRefused(why)}\n${S.current.approveRefusedHint}';

  @override
  bool get caution => true;

  @override
  List<Object?> get props => [why];
}

/// The plan waits; its record is not read yet.
final class TaskNoteWaiting extends TaskNoteVm {
  const TaskNoteWaiting();

  @override
  String get text => S.current.planWaiting;
}

/// What Approve signs, with the user's [role], and how many changes run
/// with the agent's own key.
final class TaskNoteSigns extends TaskNoteVm {
  const TaskNoteSigns({required this.role, this.byAgent = 0});

  final String role;
  final int byAgent;

  @override
  String get text => [
    S.current.approveSigns(role),
    if (byAgent > 0) S.current.approveByAgent(byAgent),
  ].join('\n');

  @override
  List<Object?> get props => [role, byAgent];
}

/// The task waits for the person's answer.
final class TaskNoteAnswer extends TaskNoteVm {
  const TaskNoteAnswer();

  @override
  String get text => S.current.answerWaitingNote;
}

/// The agent works on it.
final class TaskNoteWorking extends TaskNoteVm {
  const TaskNoteWorking();

  @override
  String get text => S.current.runningNote;
}

/// The task is done; [leftOut] are the steps its run left out.
final class TaskNoteDone extends TaskNoteVm {
  const TaskNoteDone([this.leftOut = const []]);

  final List<int> leftOut;

  @override
  String get text => leftOut.isEmpty
      ? S.current.doneNote
      : S.current.doneLeftOutNote(leftOut.join(', '));

  @override
  List<Object?> get props => [leftOut];
}

/// The task failed before its run: [error], as the link said it.
final class TaskNoteFailed extends TaskNoteVm {
  const TaskNoteFailed([this.error]);

  final String? error;

  @override
  String get text => error ?? S.current.failedNote;

  @override
  bool get caution => true;

  @override
  List<Object?> get props => [error];
}

/// The card that closes the conversation: what the task waits for, a
/// note (why the plan is not shown yet), and its buttons.
final class TaskCardVm extends Equatable {
  const TaskCardVm({
    required this.badge,
    required this.note,
    this.buttons = const [],
  });

  /// Where the task stands.
  final TaskBadge badge;
  final TaskNoteVm note;
  final List<TaskButtonVm> buttons;

  /// `Plan`, `Replaced`, or the task's state.
  String get title => switch (note) {
    TaskNoteReplaced() => S.current.replacedTitle,
    TaskNoteNoRecord() ||
    TaskNoteOtherSite() ||
    TaskNoteRefused() ||
    TaskNoteWaiting() ||
    TaskNoteSigns() => S.current.planCard,
    _ => badge.label,
  };

  bool get caution => note.caution;

  @override
  List<Object?> get props => [badge, note, buttons];
}

/// The card that closes a task's conversation: what the task waits for, a
/// note, and its buttons.
class TaskCard extends StatelessWidget {
  const TaskCard({required this.vm, required this.onButton, super.key});

  final TaskCardVm vm;
  final ValueChanged<TaskButtonVm> onButton;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      margin: Insets.assistantIndent,
      // the note's band ends at the card's rounded corners
      clipBehavior: .antiAlias,
      decoration: BoxDecoration(
        color: c.ground1,
        border: Border.all(color: c.line2),
        borderRadius: Radii.card,
      ),
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              14,
              12,
              14,
              AppSpacing.sm,
            ),
            child: SectionLabel(vm.title),
          ),
          Container(
            color: vm.caution ? c.warnTint : null,
            padding: vm.caution
                ? const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: AppSpacing.sm,
                  )
                : const EdgeInsets.fromLTRB(
                    14,
                    AppSpacing.none,
                    14,
                    12,
                  ),
            child: Text(
              vm.note.text,
              style: TextStyle(
                fontSize: FontSizes.md,
                height: LineHeights.row,
                color: vm.caution ? c.warn : c.text3,
              ),
            ),
          ),
          if (vm.buttons.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: .end,
                children: [
                  for (final b in vm.buttons)
                    if (b.primary)
                      Button.primary(
                        label: b.label,
                        disabledReason: b.disabledReason,
                        onPressed: b.disabledReason == null
                            ? () => onButton(b)
                            : null,
                      )
                    else if (b.danger)
                      Button.danger(
                        label: b.label,
                        disabledReason: b.disabledReason,
                        onPressed: b.disabledReason == null
                            ? () => onButton(b)
                            : null,
                      )
                    else
                      Button.secondary(
                        label: b.label,
                        disabledReason: b.disabledReason,
                        onPressed: b.disabledReason == null
                            ? () => onButton(b)
                            : null,
                      ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
