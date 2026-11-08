import '../../../wyrm/calls.dart';
import '../../app_state.dart';
import '../../common/action.dart';

/// `<agent>/tasks/<id>` ▸ `cancel`: planning or running stops; what was
/// done stays done.
class CancelTaskAction extends Action with WaitingAction {
  CancelTaskAction(this.id);

  final String id;

  @override
  Future<AppState?> reduce() async {
    final agent = assistant.agent;
    if (agent != null) {
      await invokeAll(deps.wyrm, '$agent/tasks/$id', 'cancel');
    }
    return null;
  }
}
