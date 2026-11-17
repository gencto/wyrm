import 'package:equatable/equatable.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';

import '../buttons/button.dart';
import '../containers/section_label.dart';
import '../indicators/app_icon.dart';
import '../indicators/quality_mark.dart';
import '../models/tone.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';
import 'blocked.dart';
import 'task_badge.dart';

/// One task in the left list.
final class TaskItemVm extends Equatable {
  const TaskItemVm({
    required this.id,
    required this.title,
    required this.badge,
    this.by,
    this.replacedBy,
    this.failedAt,
    this.noChanges = false,
    this.selected = false,
  });

  final String id;

  /// The ask, cut to two lines.
  final String title;
  final TaskBadge badge;

  /// Who asked, when it was not the user.
  final String? by;

  /// The task that took its place.
  final String? replacedBy;

  /// The step its run failed at.
  final int? failedAt;

  /// It ended without a plan: nothing changed.
  final bool noChanges;
  final bool selected;

  /// `awaiting approval`, `done`, `failed`.
  String get state => badge.label;
  Tone get tone => badge.tone;

  /// Who asked and how it ended (`by olena · failed at step 3`).
  String? get detail {
    final parts = [
      if (by case final b?) S.current.taskBy(b),
      if (replacedBy case final next?)
        S.current.taskReplaced(next)
      else if (failedAt case final n?)
        S.current.taskFailedAt(n)
      else if (noChanges)
        S.current.taskNoChanges,
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  @override
  List<Object?> get props => [
    id,
    title,
    badge,
    by,
    replacedBy,
    failedAt,
    noChanges,
    selected,
  ];
}

/// The groups of the task list.
enum TaskSection {
  /// Tasks still under way.
  now,

  /// Tasks that ended.
  earlier;

  String get label => switch (this) {
    now => S.current.sectionNow,
    earlier => S.current.sectionEarlier,
  };
}

/// A titled group of tasks (`NOW`, `EARLIER`).
final class TaskSectionVm extends Equatable {
  const TaskSectionVm({required this.section, required this.tasks});

  final TaskSection section;
  final List<TaskItemVm> tasks;

  String get label => section.label;

  @override
  List<Object?> get props => [section, tasks];
}

/// Board *Assistant*, left: New task, a note, the tasks by section, the
/// selected one with an ember bar.
class TaskList extends StatelessWidget {
  const TaskList({
    required this.sections,
    required this.onNew,
    required this.onTask,
    this.agent,
    this.noAgent = false,
    super.key,
  });

  final List<TaskSectionVm> sections;
  final VoidCallback onNew;
  final ValueChanged<String> onTask;

  /// The agent link's key, for the note; null when there is none.
  final String? agent;

  /// The site has no agent link: New task is disabled.
  final bool noAgent;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final newReason = noAgent ? const BlockedNoAgent().text : null;
    final note = S.current.taskListNote(
      agent?.split('/').skip(2).join('/') ?? 'agent',
    );
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Button.secondary(
          label: S.current.newTask,
          icon: AppIcon.uiAdd,
          expand: true,
          disabledReason: newReason,
          onPressed: newReason == null ? onNew : null,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            2,
            10,
            2,
            AppSpacing.sm,
          ),
          child: Text(
            note,
            style: TextStyle(fontSize: FontSizes.sm, color: c.text3),
          ),
        ),
        for (final s in sections) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              2,
              10,
              2,
              6,
            ),
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
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
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
                  style: TextStyle(fontSize: FontSizes.md, color: c.text1),
                ),
                Row(
                  spacing: 6,
                  children: [
                    StateMark(mark: .dot, color: color, size: 6),
                    Expanded(
                      child: Text(
                        vm.state,
                        overflow: .ellipsis,
                        style: TextStyle(
                          fontSize: FontSizes.sm,
                          color: color,
                        ),
                      ),
                    ),
                    Text(
                      vm.id,
                      style: mono(size: FontSizes.xs, color: c.text4),
                    ),
                  ],
                ),
                if (vm.detail case final d?)
                  Text(
                    d,
                    maxLines: 1,
                    overflow: .ellipsis,
                    style: TextStyle(fontSize: FontSizes.sm, color: c.text3),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
