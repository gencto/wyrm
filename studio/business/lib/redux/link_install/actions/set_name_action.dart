import '../../app_state.dart';
import '../../common/action.dart';

class SetNameAction extends Action {
  SetNameAction(this.name);

  final String? name;

  @override
  AppState reduce() => state.copyWith.linkInstall(name: name);
}
