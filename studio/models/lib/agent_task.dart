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
  }) = _AgentTask;
}
