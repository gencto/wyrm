import 'package:models/agent_task.dart';
import 'package:models/plan_step.dart';
import 'package:models/step_args_note.dart';
import 'package:models/step_kind.dart';
import 'package:models/step_status.dart';
import 'package:models/step_wait.dart';
import 'package:models/task_question.dart';
import 'package:models/task_state.dart';
import 'package:models/task_suggestion.dart';

import 'approval.dart';
import 'assistant_view.dart';
import 'decode/agent_task.dart' show refusalCode;
import 'mappers/agent_task_mapper.dart' show withheld;

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

  /// The plan waits to be approved and no task took its place.
  bool get waitsForApproval =>
      state == TaskState.awaitingApproval && replacedBy == null;

  /// The step a run stopped at, while nothing replaced the task: the
  /// Stopped card says where and what next.
  PlanStep? get stoppedAt =>
      state == TaskState.failed && replacedBy == null ? failedStep : null;

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

  /// The plan card is shown: the task has a plan.
  bool get showsPlan => plan.isNotEmpty;

  /// The choices card is shown: the assistant asked something.
  bool get showsChoices => questions.isNotEmpty;

  /// The Result card is shown: a finished plan touched keys with a value.
  bool get showsResult => touched.isNotEmpty;

  /// The run card is shown: the plan runs or ran; not before a run (a
  /// plan that waits, a rejected one).
  bool get showsRun => plan.isNotEmpty && (state == TaskState.running || ran);

  /// The run is over: no row of it changes any more.
  bool get runEnded => state != TaskState.running;

  /// Where step [s] stands while it has no result: it runs now, or the
  /// run has not reached it.
  StepWait waitOf(PlanStep s) => state == TaskState.running && s.n == step
      ? StepWait.running
      : StepWait.waiting;

  /// The fixes the plan card shows for step [n]: only while the plan
  /// waits.
  List<TaskSuggestion> fixesShownOf(int n) =>
      waitsForApproval ? fixesOf(n) : const [];

  /// Who asked, on the task's row: a recorded or replaced task someone
  /// else asked ([own]: the user asked it); null else.
  String? byOf({required bool own}) =>
      (recorded || replacedBy != null) && owner.isNotEmpty && !own
      ? ownerName
      : null;

  /// The step a recorded or replaced task failed at, on its row.
  int? get failedAt => recorded || replacedBy != null ? failedStep?.n : null;

  /// A recorded task that ended with nothing to do: no plan.
  bool get noChanges => recorded && state == TaskState.done && plan.isEmpty;
}

/// What the plan card reads off one step: computed here once, not in a
/// connector (studio-rules §3).
extension StepFacts on PlanStep {
  /// How long a `sleep` step waits, in seconds; null for any other step.
  double? get sleepSeconds => kind == StepKind.sleep ? (seconds ?? 0) : null;

  /// Its timeout as an argument of its own: every step with one but a
  /// `sleep` (whose seconds are its length).
  double? get timeoutArg => kind == StepKind.sleep ? null : seconds;

  /// Its arguments are masked because their schema is not known: the
  /// person may look at them.
  bool get argsGuessed => !argsKnown && withheld(this).isNotEmpty;

  /// The note under its arguments: all masked, or a secret not shown.
  StepArgsNote? get argsNote => argsGuessed
      ? StepArgsNote.masked
      : secret.isEmpty
      ? null
      : StepArgsNote.secret;

  /// The note under the step, for the person's [choice]: the step it
  /// needs is left out, it is left out, it runs with the agent's key, or
  /// the steps it runs after; null with nothing to say.
  StepNote? noteWith(StepChoice? choice) => switch (choice) {
    StepChoice(:final needs?) => StepNoteNeeds(needs),
    StepChoice(ticked: false) => const StepNoteLeftOut(),
    // no tick, and it runs: the person cannot leave it out
    StepChoice(byAgent: true) => const StepNoteByAgent(),
    _ when after.isNotEmpty => StepNoteAfter(after.toList()),
    _ => null,
  };
}

/// What the Assistant reads off one question.
extension QuestionFacts on TaskQuestion {
  /// The labels of the options that were picked, in the card's order.
  List<String> get pickedLabels => [
    for (final o in options)
      if (picked.contains(o.id)) o.label,
  ];
}
