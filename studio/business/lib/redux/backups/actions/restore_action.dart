import '../../app_state.dart';
import '../../common/action.dart';
import 'apply_restore_action.dart';
import 'follow_restore_action.dart';
import 'set_backup_form_action.dart';

/// *Restore* of the restore dialog: the sections the mode and the
/// session's rights do not take are left out ([drop]), the restore is
/// applied with [passphrase], and a broker that restarts for it is
/// followed until it is back. One intent, one dispatch.
///
/// Rebuilds, decided: leaving sections out is not drawn on its own
/// (`notify: false`); the apply and the follow are waiting actions.
class RestoreAction extends Action {
  RestoreAction({required this.drop, this.passphrase});

  final Set<String> drop;
  final String? passphrase;

  @override
  Future<AppState?> reduce() async {
    for (final s in drop) {
      dispatchSync(SetBackupFormAction(toggle: s), notify: false);
    }
    final status = await dispatchAndWait(
      ApplyRestoreAction(passphrase: passphrase),
    );
    if (status.isCompletedOk && backups.stage == 'restarting') {
      await dispatchAndWait(FollowRestoreAction());
    }
    return null;
  }
}
