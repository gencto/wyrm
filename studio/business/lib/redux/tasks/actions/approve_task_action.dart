import 'package:async_redux/async_redux.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:models/approval_refusal.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../../wyrm/approval.dart';
import '../../../wyrm/failures.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import 'retrieve_task_record_action.dart';

/// `<agent>/tasks/<id>` ▸ `approve {steps, plan}` (ADR 0049 §2–4): the
/// ticked steps by number and the hash of the plan as it is shown. The
/// gateway reads the stored plan, checks the user's grants for each step
/// and signs one token per step; an unticked step is skipped, with the
/// steps that need it.
///
/// A refused approval (`invalid_parameter`: another plan, a token that
/// would not outlive the waits before its step; `permission_denied`: a
/// step outside the user's grants) is no failure of the task: it keeps
/// waiting. The refusal's text is kept for the card (`assistant.refusals`)
/// and the record is read again.
///
/// [plan] and [steps] are what the person saw when they pressed Approve:
/// the hash of the plan on screen and the steps ticked there. A record
/// read or a tick changed in between makes the store differ from them;
/// nothing is sent then (the person approves what is shown, not what
/// arrived after) and the card says so.
class ApproveTaskAction extends Action with NonReentrant, WaitingAction {
  ApproveTaskAction(this.id, {required this.plan, required this.steps});

  final String id;

  /// The hash of the plan as it was shown (`planHash`).
  final String? plan;

  /// The ticked steps as they were shown, by number.
  final List<int> steps;

  @override
  Future<AppState?> reduce() async {
    final agent = assistant.agent;
    final task = tasks.table[id];
    final plan = task?.planHash;
    if (agent == null || task == null || plan == null || otherSite != null) {
      return null;
    }
    final steps = choicesOf(task).tickedSteps;
    if (steps.isEmpty) {
      return null;
    }
    // arguments masked because their schema is not known are looked at
    // before they are approved (spec assistant.md §3)
    if (unseenArgs(task, choicesOf(task)) case final n?) {
      return state.copyWith.assistant(
        refusals: assistant.refusals.add(id, ApprovalRefusal.unseen(n)),
      );
    }
    if (plan != this.plan || !listEquals(steps, this.steps)) {
      return state.copyWith.assistant(
        refusals: assistant.refusals.add(id, const ApprovalRefusal.changed()),
      );
    }
    final key = '$agent/tasks/$id';
    try {
      await deps.wyrm.agentApprove(key, steps: steps, plan: plan);
    } on WyrmException catch (e) {
      final known = e.status.known;
      if (known != Status.invalidParameter &&
          known != Status.permissionDenied) {
        throw StudioException.refused(
          e,
          key: key,
          call: const .known(.approve),
          thing: id,
          write: true,
        );
      }
      // the refusal is shown at once; the record is read again after it
      dispatchSync(_Refused(id, e.message));
      await dispatchAndWait(RetrieveTaskRecordAction(id));
      return null;
    }
    await dispatchAndWait(RetrieveTaskRecordAction(id));
    return state.copyWith.assistant(
      refusals: assistant.refusals.remove(id),
      unticked: assistant.unticked.remove(id),
    );
  }
}

/// The refusal [message] of an approval of task [id], kept for its card.
class _Refused extends Action {
  _Refused(this.id, this.message);

  final String id;
  final String message;

  @override
  AppState reduce() => state.copyWith.assistant(
    refusals: assistant.refusals.add(id, ApprovalRefusal.said(message)),
  );
}
