import 'package:models/install_field.dart';
import 'package:models/install_step.dart';

import '../../app_state.dart';
import '../../common/action.dart';

/// *Change the answers* of an install that was not made: back to the step
/// that holds the field the broker refused (the URL, the repository and
/// its ref are on the first step), with every answer kept.
class ChangeInstallAnswersAction extends Action {
  @override
  AppState reduce() => state.copyWith.linkInstall(
    step: switch (linkInstall.refusedField) {
      null || InstallField.name => InstallStep.run,
      InstallField.url ||
      InstallField.git ||
      InstallField.ref => InstallStep.choose,
    },
  );
}
