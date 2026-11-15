import 'package:models/install_phase.dart';
import 'package:models/install_step.dart';

import '../../app_state.dart';
import '../../common/action.dart';

/// An install was sent: Add a link shows its last step, waiting, and
/// forgets what the broker said of the one before.
class InstallingAction extends Action {
  @override
  AppState reduce() => state.copyWith.linkInstall(
    step: InstallStep.result,
    phase: InstallPhase.installing,
    message: null,
    refusedField: null,
    refusedSaid: null,
  );
}
