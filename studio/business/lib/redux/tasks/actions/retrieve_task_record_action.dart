import 'package:async_redux/async_redux.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/error_hint.dart';
import 'package:models/error_kind.dart';
import 'package:models/plan_step.dart';
import 'package:models/step_kind.dart';
import 'package:models/unreadable_part.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../../wyrm/decode/agent_task.dart';
import '../../../wyrm/decode/decoded.dart';
import '../../../wyrm/failures.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import 'add_tasks_action.dart';

/// Reads the record of task [id]: its `~state` document through the
/// gateway's `doc` (ADR 0049 §1): the ask, the owner, the plan with its
/// results, the log, the error. Dispatched when a task is selected and on
/// each change of its state.
///
/// A gateway older than `doc` answers `unknown op`: the assistant then
/// remembers that documents are not readable (`assistant.docs`) and shows
/// its note instead of the plan. A record the user may not read (somebody
/// else's task) leaves the task as it is.
///
/// The reads of one task run one after the other, in the order they were
/// dispatched (`Sequential`, a queue per task). Every move of the task
/// starts a read, the gateway answers each in a task of its own, and the
/// record replaces the task whole: a read sent before `done` that answered
/// after the one sent after it would leave the task `running` for good.
class RetrieveTaskRecordAction extends Action with WaitingAction, Sequential {
  RetrieveTaskRecordAction(this.id) : super(quiet: true);

  final String id;

  @override
  Object? sequentialKeyParams() => (RetrieveTaskRecordAction, id);

  @override
  Future<AppState?> reduce() async {
    final agent = assistant.agent;
    if (agent == null || !assistant.docs) {
      return null;
    }
    try {
      final key = '$agent/tasks/$id';
      final record = await deps.wyrm.doc(key, '~state');
      final task = switch (agentTaskOf(id, record)) {
        Valid(:final value) => value,
        // a record Studio cannot read is said, with the field: the task
        // stays as it was, never an empty one
        final Invalid<Object?> bad => throw StudioException.hinted(
          ErrorKind.broker,
          ErrorHint.unreadable(
            UnreadablePart.taskRecord,
            name: id,
            field: loggedField(key, bad),
          ),
          key: key,
          call: const .known(.doc),
          thing: id,
        ),
      };
      final plan = await _secrets(task.plan);
      // another site was viewed meanwhile: this is a task of its agent
      if (assistant.agent != agent) {
        return null;
      }
      dispatchSync(AddTasksAction([task.copyWith(plan: plan)].lock));
    } on WyrmException catch (e) {
      if (isUnknownOp(e)) {
        return state.copyWith.assistant(docs: false);
      }
      if (e.status.known != Status.permissionDenied &&
          e.status.known != Status.notFound) {
        rethrow;
      }
    }
    return null;
  }

  /// [plan] with the secret arguments of its `invoke` steps named
  /// (`PlanStep.secret`), from the `~meta` of each step's node: a parameter
  /// with the password editor. A node that cannot be read (it does not
  /// exist yet, `check: at_run`; or it is outside the user's rights), or
  /// one whose meta does not describe the action, gives no schema: the
  /// step is marked `argsKnown: false`, so every argument of it is masked
  /// until the person reveals it and none is written to a file (spec
  /// `assistant.md` §3, secret arguments).
  Future<IList<PlanStep>> _secrets(IList<PlanStep> plan) async {
    final metas = <String, NodeMeta?>{};
    final out = <PlanStep>[];
    for (final s in plan) {
      if (s.kind != StepKind.invoke || s.args.isEmpty) {
        out.add(s);
        continue;
      }
      if (!metas.containsKey(s.key)) {
        try {
          metas[s.key] = await deps.wyrm.meta(s.key);
        } on WyrmException {
          metas[s.key] = null;
        }
      }
      final params = metas[s.key]?.actions?[s.action]?.params;
      out.add(
        s.copyWith(
          argsKnown: params != null,
          secret: {
            for (final name in s.args.keys)
              if (params?[name]?.isPassword ?? false) name,
          }.lock,
        ),
      );
    }
    return out.lock;
  }
}
