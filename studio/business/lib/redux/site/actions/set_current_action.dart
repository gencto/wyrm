import '../../app_state.dart';
import '../../common/action.dart';

class SetCurrentAction extends Action {
  SetCurrentAction(this.current);

  final String? current;

  @override
  AppState reduce() => state.copyWith.site(current: current);
}
