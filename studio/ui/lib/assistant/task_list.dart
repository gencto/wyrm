import 'package:equatable/equatable.dart';
import 'package:material_ui/material_ui.dart';

import '../buttons/button.dart';
import '../containers/section_label.dart';
import '../indicators/quality_mark.dart';
import '../models/tone.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/typography.dart';

/// One task in the left list.
final class TaskItemVm extends Equatable {
  const TaskItemVm({
    required this.id,
    required this.title,
    required this.state,
    required this.tone,
    this.detail,
    this.selected = false,
  });

  final String id;

  /// The ask, cut to two lines.
  final String title;

  /// `awaiting approval`, `done`, `failed`.
  final String state;
  final Tone tone;

  /// Who asked and how it ended (`by olena · failed at step 3`).
  final String? detail;
  final bool selected;

  @override
  List<Object?> get props => [id, title, state, tone, detail, selected];
}

/// A titled group of tasks (`NOW`, `EARLIER`).
final class TaskSectionVm extends Equatable {
  const TaskSectionVm({required this.label, required this.tasks});

  final String label;
  final List<TaskItemVm> tasks;

  @override
  List<Object?> get props => [label, tasks];
}

/// Board *Assistant*, left: New task, a note, the tasks by section, the
/// selected one with an ember bar.
class TaskList extends StatelessWidget {
  const TaskList({
    required this.newLabel,
    required this.note,
    required this.sections,
    required this.onNew,
    required this.onTask,
    this.newReason,
    super.key,
  });

  final String newLabel;
  final String note;
  final List<TaskSectionVm> sections;
  final VoidCallback onNew;
  final ValueChanged<String> onTask;
  final String? newReason;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Button.secondary(
          label: newLabel,
          icon: 'ui_add',
          expand: true,
          disabledReason: newReason,
          onPressed: newReason == null ? onNew : null,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 10, 2, 8),
          child: Text(note, style: TextStyle(fontSize: 12, color: c.text3)),
        ),
        for (final s in sections) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 10, 2, 6),
            child: SectionLabel(s.label),
          ),
          for (final t in s.tasks) _Task(vm: t, onTap: () => onTask(t.id)),
        ],
      ],
    );
  }
}

class _Task extends StatelessWidget {
  const _Task({required this.vm, required this.onTap});

  final TaskItemVm vm;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = vm.tone == .neutral ? c.text3 : toneColor(c, vm.tone);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: vm.selected ? c.emberFill : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: Radii.control,
          side: vm.selected ? BorderSide(color: c.emberLine) : BorderSide.none,
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: Radii.control,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Column(
              crossAxisAlignment: .start,
              spacing: 4,
              children: [
                Text(
                  vm.title,
                  maxLines: 2,
                  overflow: .ellipsis,
                  style: TextStyle(fontSize: 13, color: c.text1),
                ),
                Row(
                  spacing: 6,
                  children: [
                    StateMark(mark: .dot, color: color, size: 6),
                    Expanded(
                      child: Text(
                        vm.state,
                        overflow: .ellipsis,
                        style: TextStyle(fontSize: 12, color: color),
                      ),
                    ),
                    Text(vm.id, style: mono(size: 11, color: c.text4)),
                  ],
                ),
                if (vm.detail case final d?)
                  Text(
                    d,
                    maxLines: 1,
                    overflow: .ellipsis,
                    style: TextStyle(fontSize: 12, color: c.text3),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
