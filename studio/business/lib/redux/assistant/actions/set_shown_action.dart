import '../../app_state.dart';
import '../../common/action.dart';

class SetShownAction extends Action {
  SetShownAction(this.shown);

  final bool shown;

  @override
  AppState reduce() => state.copyWith.assistant(shown: shown);
}
