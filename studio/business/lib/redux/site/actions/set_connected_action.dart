import '../../app_state.dart';
import '../../common/action.dart';

class SetConnectedAction extends Action {
  SetConnectedAction(this.connected);

  final bool connected;

  @override
  AppState reduce() => state.copyWith.site(connected: connected);
}
