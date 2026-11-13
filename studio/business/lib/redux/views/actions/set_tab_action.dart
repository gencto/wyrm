import '../../app_state.dart';
import '../../common/action.dart';

class SetTabAction extends Action {
  SetTabAction(this.tab);

  final String tab;

  @override
  AppState reduce() => state.copyWith.views(tab: tab);
}
