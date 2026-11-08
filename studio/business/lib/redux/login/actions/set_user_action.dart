import '../../app_state.dart';
import '../../common/action.dart';

class SetUserAction extends Action {
  SetUserAction(this.user);

  final String? user;

  @override
  AppState reduce() => state.copyWith.login(user: user);
}
