import '../../app_state.dart';
import '../../common/action.dart';

class SetStepAction extends Action {
  SetStepAction(this.step);

  final int step;

  @override
  AppState reduce() => state.copyWith.linkInstall(step: step);
}
