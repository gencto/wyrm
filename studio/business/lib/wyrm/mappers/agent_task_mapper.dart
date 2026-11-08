import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/agent_task.dart';
import 'package:models/plan_step.dart';
import 'package:models/task_state.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'values.dart';

/// `tasks/<id>` `~state` of the agent link as an [AgentTask]:
/// `{state, ask, owner, plan[], log[], error?, tokens}`.
AgentTask agentTaskOf(String id, Value v) => AgentTask(
  id: id,
  state: taskStateOf(str(v['state'])),
  owner: str(v['owner']) ?? '',
  ask: str(v['ask']) ?? str(v['task']) ?? '',
  plan: switch (v['plan']) {
    VArray(:final v) => [for (final s in v) planStepOf(s)].lock,
    _ => const IListConst([]),
  },
  log: switch (v['log']) {
    VArray(:final v) => [for (final l in v) text(l) ?? '$l'].lock,
    _ => const IListConst([]),
  },
  error: text(v['error']),
  tokens: integer(v['tokens']) ?? 0,
);

/// The task states of the agent link (and the ones it adds later).
TaskState taskStateOf(String? s) => switch (s) {
  'awaiting_approval' || 'approval' || 'planned' => TaskState.awaitingApproval,
  'running' || 'approved' => TaskState.running,
  'done' || 'completed' => TaskState.done,
  'failed' || 'rejected' || 'cancelled' || 'canceled' => TaskState.failed,
  _ => TaskState.planning,
};

/// One step `{op, key, action?, args, level, approval, reason?}`.
PlanStep planStepOf(Value v) => PlanStep(
  op: str(v['op']) ?? (v['action'] != null ? 'invoke' : 'set'),
  key: str(v['key']) ?? '',
  action: str(v['action']),
  args: switch (toDart(v['args'])) {
    final Map<String, Object?> m => m.lock,
    final Object o => {'value': o}.lock,
    null => const IMapConst({}),
  },
  level: str(v['level']) ?? 'write',
  approval: boolean(v['approval']) ?? false,
  reason: str(v['reason']),
);
