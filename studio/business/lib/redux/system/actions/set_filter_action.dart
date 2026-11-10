import '../../app_state.dart';
import '../../common/action.dart';

/// The text `get_log` looks for in the target or the message.
class SetFilterAction extends Action {
  SetFilterAction(this.filter);

  final String? filter;

  @override
  AppState reduce() => state.copyWith.system(filter: filter);
}
