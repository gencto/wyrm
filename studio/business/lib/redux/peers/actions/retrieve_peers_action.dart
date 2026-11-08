import '../../app_state.dart';
import '../../common/action.dart';

class RetrievePeersAction extends Action with WaitingAction {
  @override
  Future<AppState?> reduce() => Future.value(state);
}
