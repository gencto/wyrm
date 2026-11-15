import '../../app_state.dart';
import '../../common/action.dart';

class SetMenuAskedAction extends Action {
  SetMenuAskedAction(this.menuAsked);

  final String? menuAsked;

  @override
  AppState reduce() => state.copyWith.nodes(menuAsked: menuAsked);
}
