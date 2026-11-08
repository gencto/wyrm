import '../../app_state.dart';
import '../../common/action.dart';

class SetWatchRefusedAction extends Action {
  SetWatchRefusedAction(this.watchRefused);

  final String? watchRefused;

  @override
  AppState reduce() => state.copyWith.flowEditor(watchRefused: watchRefused);
}
