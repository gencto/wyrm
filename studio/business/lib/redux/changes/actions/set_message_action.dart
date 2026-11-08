import '../../app_state.dart';
import '../../common/action.dart';

class SetMessageAction extends Action {
  SetMessageAction(this.message);

  final String? message;

  @override
  AppState reduce() => state.copyWith.changes(message: message);
}
