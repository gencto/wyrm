import '../../app_state.dart';
import '../../common/action.dart';

class SetActionAction extends Action {
  SetActionAction(this.action);

  final String? action;

  @override
  AppState reduce() => state.copyWith.nodes(action: action);
}
