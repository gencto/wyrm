import '../../app_state.dart';
import '../../common/action.dart';
import 'estimate_backup_action.dart';
import 'retrieve_send_connections_action.dart';
import 'set_backup_form_action.dart';

/// A choice of the backup dialog ([change]) that a read follows: the
/// history days or a link of a broker backup (the estimate is read again),
/// the file-store link to send to (its connections are read), or where a
/// backup goes (to a file store the host names one link for: that link,
/// and its connections).
///
/// The change is in the store before the read starts, so the read takes
/// it. Rebuilds, decided: [change] notifies on its own (the dialog shows
/// the choice at once); the read is its own waiting action.
class ChangeBackupFormAction extends Action {
  /// The history days or a link changed: the estimate is read again.
  ChangeBackupFormAction.estimate(this.change)
    : _connectionsOf = null,
      _where = false;

  /// The file-store link changed: its connections are read.
  ChangeBackupFormAction.sendLink(String link)
    : change = SetBackupFormAction(sendLink: link),
      _connectionsOf = link,
      _where = false;

  /// Where the backup goes changed ([where]: `computer`, `store`).
  ChangeBackupFormAction.where(String where)
    : change = SetBackupFormAction(where: where),
      _connectionsOf = null,
      _where = true;

  final SetBackupFormAction change;
  final String? _connectionsOf;
  final bool _where;

  @override
  Future<AppState?> reduce() async {
    if (_where) {
      final links = backups.sendLinks;
      // One link the host lists for a file store: it is the choice, in the
      // same state as the place.
      final only = change.where == 'store' && links.length == 1
          ? links.first.link
          : null;
      dispatchSync(change, notify: only == null);
      if (only != null) {
        dispatchSync(SetBackupFormAction(sendLink: only));
        await dispatchAndWait(RetrieveSendConnectionsAction(only));
      }
      return null;
    }
    dispatchSync(change);
    await dispatchAndWait(switch (_connectionsOf) {
      final link? => RetrieveSendConnectionsAction(link),
      null => EstimateBackupAction(),
    });
    return null;
  }
}
