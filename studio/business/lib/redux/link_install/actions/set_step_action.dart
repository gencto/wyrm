import 'package:models/install_step.dart';

import '../../app_state.dart';
import '../../common/action.dart';

/// The step of Add a link on screen.
class SetStepAction extends Action {
  SetStepAction(this.step);

  final InstallStep step;

  @override
  AppState? reduce() =>
      step == linkInstall.step ? null : state.copyWith.linkInstall(step: step);
}
