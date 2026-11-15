import '../../app_state.dart';
import '../../common/action.dart';
import 'estimate_backup_action.dart';
import 'retrieve_send_connections_action.dart';
import 'set_backup_form_action.dart';

/// A choice of the backup dialog ([change]) that a read follows: the
/// history days or a link of a broker backup (the estimate is read again),
/// or the file-store link to send to (its connections are read).
///
/// The change is in the store before the read starts, so the read takes
/// it. Rebuilds, decided: [change] notifies on its own (the dialog shows
/// the choice at once); the read is its own waiting action.
class ChangeBackupFormAction extends Action {
  /// The history days or a link changed: the estimate is read again.
  ChangeBackupFormAction.estimate(this.change) : _connectionsOf = null;

  /// The file-store link changed: its connections are read.
  ChangeBackupFormAction.sendLink(String link)
    : change = SetBackupFormAction(sendLink: link),
      _connectionsOf = link;

  final SetBackupFormAction change;
  final String? _connectionsOf;

  @override
  Future<AppState?> reduce() async {
    dispatchSync(change);
    await dispatchAndWait(switch (_connectionsOf) {
      final link? => RetrieveSendConnectionsAction(link),
      null => EstimateBackupAction(),
    });
    return null;
  }
}
