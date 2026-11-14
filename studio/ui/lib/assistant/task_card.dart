import 'package:equatable/equatable.dart';
import 'package:material_ui/material_ui.dart';

import '../buttons/button.dart';
import '../containers/section_label.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';

/// A button under the selected task (Approve, Reject, Cancel).
final class TaskButtonVm extends Equatable {
  const TaskButtonVm({
    required this.id,
    required this.label,
    this.primary = false,
    this.danger = false,
    this.disabledReason,
  });

  final String id;
  final String label;
  final bool primary;
  final bool danger;
  final String? disabledReason;

  @override
  List<Object?> get props => [id, label, primary, danger, disabledReason];
}

/// The card that closes the conversation: what the task waits for, a
/// note (why the plan is not shown yet), and its buttons.
final class TaskCardVm extends Equatable {
  const TaskCardVm({
    required this.title,
    required this.note,
    this.caution = false,
    this.buttons = const [],
  });

  final String title;
  final String note;

  /// The note asks for attention (a plan that waits, a task that failed):
  /// it is drawn on the warning tint. Else it is plain grey text.
  final bool caution;
  final List<TaskButtonVm> buttons;

  @override
  List<Object?> get props => [title, note, caution, buttons];
}

/// The card that closes a task's conversation: what the task waits for, a
/// note, and its buttons.
class TaskCard extends StatelessWidget {
  const TaskCard({required this.vm, required this.onButton, super.key});

  final TaskCardVm vm;
  final ValueChanged<String> onButton;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      margin: const EdgeInsets.only(left: 42),
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
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: SectionLabel(vm.title),
          ),
          Container(
            color: vm.caution ? c.warnTint : null,
            padding: vm.caution
                ? const EdgeInsets.symmetric(horizontal: 14, vertical: 8)
                : const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: Text(
              vm.note,
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
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
                            ? () => onButton(b.id)
                            : null,
                      )
                    else if (b.danger)
                      Button.danger(
                        label: b.label,
                        disabledReason: b.disabledReason,
                        onPressed: b.disabledReason == null
                            ? () => onButton(b.id)
                            : null,
                      )
                    else
                      Button.secondary(
                        label: b.label,
                        disabledReason: b.disabledReason,
                        onPressed: b.disabledReason == null
                            ? () => onButton(b.id)
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
