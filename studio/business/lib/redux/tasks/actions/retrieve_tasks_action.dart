import '../../app_state.dart';
import '../../common/action.dart';

class RetrieveTasksAction extends Action with WaitingAction {
  @override
  Future<AppState?> reduce() => Future.value(state);
}
