import 'dart:async';

import 'package:async_redux/async_redux.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:wyrm_client/wyrm_client.dart';

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

  /// The refusal kept when the plan or the ticks moved after they were
  /// shown.
  static const changed =
      'the plan or its ticks changed after they were shown. Read the plan '
      'again and approve what it says now.';

  @override
  Future<AppState?> reduce() async {
    final agent = assistant.agent;
    final task = tasks.table[id];
    final plan = task?.planHash;
    if (agent == null || task == null || plan == null || otherSite != null) {
      return null;
    }
    final steps = [
      for (final c in choicesOf(task))
        if (c.ticked ?? false) c.n,
    ];
    if (steps.isEmpty) {
      return null;
    }
    if (plan != this.plan || !listEquals(steps, this.steps)) {
      return state.copyWith.assistant(
        refusals: assistant.refusals.add(id, changed),
      );
    }
    final key = '$agent/tasks/$id';
    try {
      await deps.wyrm.approveTask(key, steps: steps, plan: plan);
    } on WyrmException catch (e) {
      final known = e.status.known;
      if (known != Status.invalidParameter &&
          known != Status.permissionDenied) {
        throw StudioException.refused(
          e,
          key: key,
          call: 'approve',
          thing: id,
          write: true,
        );
      }
      unawaited(dispatchAndWait(RetrieveTaskRecordAction(id)));
      return state.copyWith.assistant(
        refusals: assistant.refusals.add(id, e.message),
      );
    }
    await dispatchAndWait(RetrieveTaskRecordAction(id));
    return state.copyWith.assistant(
      refusals: assistant.refusals.remove(id),
      unticked: assistant.unticked.remove(id),
    );
  }
}
