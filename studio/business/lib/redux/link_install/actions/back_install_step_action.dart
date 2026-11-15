import 'package:models/install_phase.dart';
import 'package:models/install_step.dart';

import '../../app_state.dart';
import '../../common/action.dart';

/// *Back* of Add a link past its first step: from the result of an
/// install that was not made, back to Where it runs (every answer kept);
/// else to the step before. Null on the first step (the page closes
/// instead) and after an install that was made.
class BackInstallStepAction extends Action {
  @override
  AppState? reduce() {
    final steps = installSteps;
    final at = steps.indexOf(linkInstall.step);
    if (at <= 0 ||
        (linkInstall.step == InstallStep.result &&
            linkInstall.phase == InstallPhase.done)) {
      return null;
    }
    final run = steps.indexOf(InstallStep.run);
    return state.copyWith.linkInstall(
      step: run < at ? InstallStep.run : steps[at - 1],
    );
  }
}
