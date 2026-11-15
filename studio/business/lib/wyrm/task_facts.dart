import 'package:models/agent_task.dart';
import 'package:models/plan_step.dart';
import 'package:models/step_status.dart';
import 'package:models/task_question.dart';
import 'package:models/task_state.dart';
import 'package:models/task_suggestion.dart';

import 'decode/agent_task.dart' show refusalCode;

/// What the Assistant reads off one task: computed here once, not in a
/// connector (studio-rules §3).
extension TaskFacts on AgentTask {
  /// The first step of the run that failed.
  PlanStep? get failedStep =>
      plan.where((s) => s.result?.status == StepStatus.failed).firstOrNull;

  /// The numbers of the steps a run left out.
  List<int> get leftOut => [
    for (final s in plan)
      if (s.result?.status == StepStatus.skipped) s.n,
  ];

  /// What the run changed and keeps: the steps that change something and
  /// ended `ok` (a cancel marks no step failed; a skipped step did nothing).
  List<int> get kept => [
    for (final s in plan)
      if (s.kind.changes && s.result?.status == StepStatus.ok) s.n,
  ];

  /// A step has a result: the plan ran, or runs.
  bool get ran => plan.any((s) => s.result != null);

  /// How long the run took, from its first step's end to its last's.
  int get ranSeconds {
    final times = [for (final s in plan) ?s.result?.time];
    return times.length < 2 ? 0 : times.last.difference(times.first).inSeconds;
  }

  /// The keys with a value that a finished plan touched: what it set and
  /// what it proved, at most 12, in the plan's order.
  List<String> get touched => state != TaskState.done
      ? const []
      : {
          for (final s in plan)
            if (s.result?.status == StepStatus.ok && s.kind.leavesValue) s.key,
        }.take(12).toList();

  /// The node a finished plan was about: the target of its last step that
  /// changed something.
  String? get changedNode => plan
      .where((s) => s.result?.status == StepStatus.ok && s.kind.changes)
      .map((s) => s.key)
      .lastOrNull;

  /// A question of the task still waits for its answer.
  bool get asksStill => questions.any((q) => !q.answered);

  /// The task's title: its ask, or its id before the ask is known.
  String get title => ask.isEmpty ? id : ask;

  /// The subject who asked, without `user:`.
  String get ownerName => owner.replaceFirst('user:', '');

  /// Why the run stopped, as the link said it: the failed step's answer,
  /// else the task's error; null when neither says anything.
  String? get stopMessage => switch (failedStep?.result?.message) {
    final m? when m.isNotEmpty => m,
    _ => error,
  };

  /// The fixed word [stopMessage] starts with (`out_of_range`), if any.
  String? get stopCode => switch (stopMessage) {
    final m? => refusalCode(m),
    null => null,
  };

  /// The fixes the model offers for step [n].
  List<TaskSuggestion> fixesOf(int n) => [
    for (final s in suggestions)
      if (s.step == n) s,
  ];

  /// The ways out of a stopped run: the suggestions without rows (those
  /// need ticks the Stopped card does not show).
  List<TaskSuggestion> get waysOut => [
    for (final s in suggestions)
      if (s.rows.isEmpty) s,
  ];

  /// *Same for more units?*: the suggestions with rows.
  List<TaskSuggestion> get withRows => [
    for (final s in suggestions)
      if (s.rows.isNotEmpty) s,
  ];

  /// The drawer's second button (spec §5): the first suggestion without a
  /// step and without rows.
  TaskSuggestion? get second =>
      suggestions.where((s) => s.step == null && s.rows.isEmpty).firstOrNull;
}

/// What the Assistant reads off one question.
extension QuestionFacts on TaskQuestion {
  /// The labels of the options that were picked, in the card's order.
  List<String> get pickedLabels => [
    for (final o in options)
      if (picked.contains(o.id)) o.label,
  ];
}
