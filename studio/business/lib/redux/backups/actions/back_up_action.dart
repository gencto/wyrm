import 'package:models/backup_section.dart';

import '../../app_state.dart';
import '../../common/action.dart';
import 'create_backup_action.dart';
import 'set_backup_form_action.dart';

/// *Back up* of the backup dialog, with the [passphrase] typed in it. One
/// intent, one dispatch.
///
/// What goes is decided here, not by the dialog: the plan of the form
/// (`backupFormPlan`) says whether `keys` goes (only with a passphrase
/// the broker takes; else it is unticked first, so the form shows what
/// was sent) and whether the backup may start at all
/// ([CreateBackupAction] refuses a blocked one).
///
/// Rebuilds, decided: leaving `keys` out is not drawn on its own
/// (`notify: false`); the creation's wait notifies.
class BackUpAction extends Action {
  BackUpAction({this.passphrase});

  final String? passphrase;

  @override
  Future<AppState?> reduce() async {
    final plan = backupFormPlan(passphraseLength: passphrase?.length ?? 0);
    if (plan.canRun && plan.dropKeys) {
      dispatchSync(
        SetBackupFormAction(toggle: BackupSection.keys),
        notify: false,
      );
    }
    await dispatchAndWait(CreateBackupAction(passphrase: passphrase));
    return null;
  }
}
