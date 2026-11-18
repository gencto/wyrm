import 'package:models/backup_stage.dart';

import '../../app_state.dart';
import '../../common/action.dart';
import 'apply_restore_action.dart';
import 'follow_restore_action.dart';
import 'set_backup_form_action.dart';

/// *Restore* of the restore dialog, with the [passphrase] typed in it:
/// the restore is applied, and a broker that restarts for it is followed
/// until it is back. One intent, one dispatch.
///
/// What goes is decided here, not by the dialog: the plan of the form
/// (`restorePlan`) names the sections the mode and the session's rights
/// do not take (they are unticked first, so the form shows what was
/// sent), and [ApplyRestoreAction] refuses a restore its plan blocks.
///
/// Rebuilds, decided: leaving sections out is not drawn on its own
/// (`notify: false`); the apply and the follow are waiting actions.
class RestoreAction extends Action {
  RestoreAction({this.passphrase});

  final String? passphrase;

  @override
  Future<AppState?> reduce() async {
    final plan = restorePlan(passphraseLength: passphrase?.length ?? 0);
    if (plan.canRun) {
      for (final s in plan.drop) {
        dispatchSync(SetBackupFormAction(toggle: s), notify: false);
      }
    }
    final status = await dispatchAndWait(
      ApplyRestoreAction(passphrase: passphrase),
    );
    if (status.isCompletedOk && backups.stage == BackupStage.restarting) {
      await dispatchAndWait(FollowRestoreAction());
    }
    return null;
  }
}
