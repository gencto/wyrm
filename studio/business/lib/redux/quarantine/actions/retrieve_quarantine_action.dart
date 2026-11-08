import '../../app_state.dart';
import '../../common/action.dart';

class RetrieveQuarantineAction extends Action with WaitingAction {
  @override
  Future<AppState?> reduce() => Future.value(state);
}
