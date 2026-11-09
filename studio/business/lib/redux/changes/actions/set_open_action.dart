import '../../app_state.dart';
import '../../common/action.dart';

class SetOpenAction extends Action {
  SetOpenAction(this.open);

  final bool open;

  @override
  AppState reduce() => state.copyWith.changes(open: open);
}
