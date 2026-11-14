import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/agent_task.dart';
import 'package:models/plan_step.dart';
import 'package:models/step_result.dart';
import 'package:models/task_option.dart';
import 'package:models/task_question.dart';
import 'package:models/task_state.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'values.dart';

/// `tasks/<id>` `~state` of the agent link as an [AgentTask]:
/// `{state, ask, owner, plan[], plan_hash, parent?, log[], error?, tokens}`
/// (ADR 0049). The plan's hash is made here from the plan as read, so an
/// approval names the plan that is shown.
AgentTask agentTaskOf(String id, Value v) => AgentTask(
  id: id,
  state: taskStateOf(str(v['state'])),
  owner: str(v['owner']) ?? '',
  ask: str(v['ask']) ?? str(v['task']) ?? '',
  plan: switch (v['plan']) {
    VArray(:final v) => [
      for (final (i, s) in v.indexed) planStepOf(s, i + 1),
    ].lock,
    _ => const IListConst([]),
  },
  planHash: planHash(v['plan']),
  questions: switch (v['questions']) {
    VArray(:final v) => [for (final q in v) questionOf(q)].lock,
    _ => const IListConst([]),
  },
  step: integer(v['step']) ?? 0,
  parent: str(v['parent']),
  log: switch (v['log']) {
    VArray(:final v) => [for (final l in v) text(l) ?? '$l'].lock,
    _ => const IListConst([]),
  },
  error: text(v['error']),
  tokens: integer(v['tokens']) ?? 0,
  recorded: true,
);

/// The task states of the agent link (and the ones it adds later).
TaskState taskStateOf(String? s) => switch (s) {
  'awaiting_approval' || 'approval' || 'planned' => TaskState.awaitingApproval,
  'awaiting_answer' => TaskState.awaitingAnswer,
  'running' || 'approved' => TaskState.running,
  'done' || 'completed' => TaskState.done,
  'failed' || 'rejected' || 'cancelled' || 'canceled' => TaskState.failed,
  _ => TaskState.planning,
};

/// A question of `~state.questions[]`: `{id, text, options: [{id, label,
/// detail}], multiple, free_text, answer?}`; `answer` is the picked option
/// ids (an array) or the person's own words (text).
TaskQuestion questionOf(Value v) {
  final answer = v['answer'];
  return TaskQuestion(
    id: str(v['id']) ?? '',
    text: str(v['text']) ?? '',
    options: switch (v['options']) {
      VArray(:final v) => [
        for (final o in v)
          TaskOption(
            id: str(o['id']) ?? '',
            label: str(o['label']) ?? '',
            detail: str(o['detail']) ?? '',
          ),
      ].lock,
      _ => const IListConst([]),
    },
    multiple: boolean(v['multiple']) ?? false,
    freeText: boolean(v['free_text']) ?? false,
    answered: answer != null,
    picked: switch (answer) {
      VArray(:final v) => [for (final a in v) ?str(a)].lock,
      _ => const IListConst([]),
    },
    words: str(answer),
  );
}

/// The plan of [t] as a file for `wyrm-agent run` (`{"steps": […]}`,
/// docs/agent.md): each step as it stands in the record, without what is
/// said about it (number, level, check, reason, result).
Map<String, Object?> planFile(AgentTask t) => {
  'about': t.ask,
  'steps': [
    for (final s in t.plan)
      switch (s.op) {
        'set' => {'set': s.key, 'value': s.args['value']},
        'invoke' => {
          'invoke': s.key,
          'action': s.action ?? '',
          'args': s.args.unlock,
        },
        'wait' => {'wait': s.key, 'timeout_s': s.seconds ?? 10},
        'expect' => {
          'expect': s.key,
          ...s.args.unlock,
          'timeout_s': s.seconds ?? 10,
        },
        _ => {'sleep_s': s.seconds ?? 0},
      },
  ],
};

/// One step in the `wyrm-agent run` format: `{set, value}`,
/// `{invoke, action, args}`, `{wait, timeout_s}`,
/// `{expect, equals | min/max | changes, timeout_s}`, `{sleep_s}`, with
/// `n, level, after?, approval, check, warn?, reason?, result?`. A step of
/// an agent link older than ADR 0049 (`{op, key, args}`) still reads.
PlanStep planStepOf(Value v, [int place = 0]) {
  final op = ['set', 'invoke', 'wait', 'expect'].firstWhere(
    (k) => v[k] is VStr,
    orElse: () => v['sleep_s'] != null ? 'sleep' : (str(v['op']) ?? 'set'),
  );
  final args = switch (op) {
    'set' when v['set'] != null => {'value': toDart(v['value'])},
    'expect' => {
      for (final k in ['equals', 'min', 'max', 'changes'])
        if (v[k] != null) k: toDart(v[k]),
    },
    'wait' || 'sleep' => const <String, Object?>{},
    _ => switch (toDart(v['args'])) {
      final Map<String, Object?> m => m,
      final Object o => {'value': o},
      null => const <String, Object?>{},
    },
  };
  final result = v['result'];
  return PlanStep(
    op: op,
    key: str(v[op]) ?? str(v['node']) ?? str(v['key']) ?? '',
    n: integer(v['n']) ?? place,
    action: str(v['action']),
    args: args.lock,
    seconds: (number(v['timeout_s']) ?? number(v['sleep_s']))?.toDouble(),
    level: str(v['level']) ?? 'write',
    approval: boolean(v['approval']) ?? false,
    check: str(v['check']) ?? 'now',
    warn: str(v['warn']),
    after: switch (v['after']) {
      VArray(:final v) => [for (final a in v) ?integer(a)].lock,
      _ => const IListConst([]),
    },
    reason: str(v['reason']),
    result: result == null
        ? null
        : StepResult(
            status: str(result['status']) ?? 'ok',
            message: str(result['message']) ?? '',
            time: switch (integer(result['time'])) {
              final int t when t > 0 => DateTime.fromMillisecondsSinceEpoch(
                t * 1000,
              ),
              _ => null,
            },
          ),
  );
}
