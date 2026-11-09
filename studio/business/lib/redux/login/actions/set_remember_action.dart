import '../../app_state.dart';
import '../../common/action.dart';

class SetRememberAction extends Action {
  SetRememberAction(this.remember);

  final bool remember;

  @override
  AppState reduce() => state.copyWith.login(remember: remember);
}
