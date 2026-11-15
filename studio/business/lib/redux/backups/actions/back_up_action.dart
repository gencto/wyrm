import '../../app_state.dart';
import '../../common/action.dart';
import 'create_backup_action.dart';
import 'set_backup_form_action.dart';

/// *Back up* of the backup dialog: `keys` goes only with a passphrase the
/// broker takes, so it is left out first when [dropKeys]; then the backup
/// is made with [passphrase]. One intent, one dispatch.
///
/// Rebuilds, decided: leaving `keys` out is not drawn on its own
/// (`notify: false`); the creation's wait notifies.
class BackUpAction extends Action {
  BackUpAction({required this.dropKeys, this.passphrase});

  final bool dropKeys;
  final String? passphrase;

  @override
  Future<AppState?> reduce() async {
    if (dropKeys) {
      dispatchSync(SetBackupFormAction(toggle: 'keys'), notify: false);
    }
    await dispatchAndWait(CreateBackupAction(passphrase: passphrase));
    return null;
  }
}
