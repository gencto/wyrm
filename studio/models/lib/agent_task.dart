import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'plan_step.dart';
import 'task_state.dart';

part 'agent_task.freezed.dart';

@freezed
abstract class AgentTask with _$AgentTask {
  /// A task of the agent link (`tasks/<id>` `~state`).
  const factory AgentTask({
    required String id,
    @Default(TaskState.planning) TaskState state,
    @Default('') String owner,
    @Default('') String ask,
    @Default(IListConst([])) IList<PlanStep> plan,
    @Default(IListConst([])) IList<String> log,
    String? error,
    @Default(0) int tokens,

    /// The hash of [plan] as it was read: what an approval is bound to.
    String? planHash,

    /// The step the run is at (its number; 0 before a run), from the
    /// public `~val.step` and the record.
    @Default(0) int step,

    /// The task this one follows.
    String? parent,

    /// The record (`~state`) was read; before that only the state is known.
    @Default(false) bool recorded,
  }) = _AgentTask;
}
