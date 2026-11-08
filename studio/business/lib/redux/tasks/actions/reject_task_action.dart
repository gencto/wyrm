import '../../app_state.dart';
import '../../common/action.dart';

class RejectTaskAction extends Action with WaitingAction {
  // TODO(frx): async work guarded by the waiting barrier (see WaitingAction).
  @override
  Future<AppState?> reduce() async => null;
}
