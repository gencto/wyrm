import 'package:async_redux/async_redux.dart';
import 'package:models/install_path.dart';
import 'package:models/install_step.dart';

import '../../../wyrm/transfer.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import 'check_package_action.dart';
import 'install_backup_action.dart';
import 'install_link_action.dart';

/// A link backup Add a link holds open: its bytes are read from it in
/// parts ([read]) and are in no state.
final class HeldFile {
  const HeldFile({required this.read, required this.size});

  final PartReader read;
  final int size;
}

/// *Continue* (or *Install*) of Add a link, one intent: Choose of a custom
/// package or a backup checks what was brought, then moves on; Where it
/// runs installs; any other step moves on.
///
/// [passphrase] and [file] come from the wizard's own state (the backup's
/// passphrase and its open file) and go nowhere else. A backup Studio can
/// hold ([CheckPackageAction.backupReadMax]) is read once for its manifest;
/// its bytes go to the check and are kept nowhere.
class ContinueInstallAction extends Action with NonReentrant {
  ContinueInstallAction({this.passphrase = '', this.file});

  final String passphrase;
  final HeldFile? file;

  @override
  Future<AppState?> reduce() async {
    final li = linkInstall;
    final steps = installSteps;
    final at = steps.indexOf(li.step);
    if (at < 0 || at + 1 >= steps.length) {
      return null;
    }
    final backup = li.path == InstallPath.backup;
    switch (li.step) {
      case InstallStep.run:
        if (backup) {
          if (file case final f?) {
            await dispatchAndWait(
              InstallBackupAction(read: f.read, passphrase: passphrase),
            );
          }
        } else {
          await dispatchAndWait(InstallLinkAction());
        }
        return null;
      case InstallStep.choose when backup:
        final f = file;
        final small = f != null && f.size <= CheckPackageAction.backupReadMax;
        // the checks are shown with the step after this one, in one state
        await dispatchAndWait(
          CheckPackageAction(backup: small ? await f.read(0, f.size) : null),
          notify: false,
        );
      case InstallStep.choose when li.path == InstallPath.custom:
        await dispatchAndWait(CheckPackageAction(), notify: false);
      case InstallStep.choose || InstallStep.check || InstallStep.result:
        break;
    }
    return state.copyWith.linkInstall(step: steps[at + 1]);
  }
}
