import '../../app_state.dart';
import '../../common/action.dart';

class SetPanelAction extends Action {
  SetPanelAction(this.panel);

  final String panel;

  @override
  AppState reduce() => state.copyWith.assistant(panel: panel);
}
