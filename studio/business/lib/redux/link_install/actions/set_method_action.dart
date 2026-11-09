import '../../app_state.dart';
import '../../common/action.dart';

class SetMethodAction extends Action {
  SetMethodAction(this.method);

  final String method;

  @override
  AppState reduce() => state.copyWith.linkInstall(method: method);
}
