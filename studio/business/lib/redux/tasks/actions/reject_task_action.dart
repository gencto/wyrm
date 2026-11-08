import 'package:wyrm_client/wyrm_client.dart';

import '../../../wyrm/calls.dart';
import '../../app_state.dart';
import '../../common/action.dart';

/// `<agent>/tasks/<id>` ▸ `reject {reason}`: the plan is not run.
class RejectTaskAction extends Action with WaitingAction {
  RejectTaskAction(this.id, {this.reason = ''});

  final String id;
  final String reason;

  @override
  Future<AppState?> reduce() async {
    final agent = assistant.agent;
    if (agent != null) {
      await invokeAll(
        deps.wyrm,
        '$agent/tasks/$id',
        'reject',
        Value.from({if (reason.isNotEmpty) 'reason': reason}),
      );
    }
    return null;
  }
}
