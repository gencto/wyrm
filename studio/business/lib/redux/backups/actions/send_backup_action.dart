import 'package:async_redux/async_redux.dart';

import '../../../wyrm/calls.dart';
import '../../../wyrm/failures.dart';
import '../../app_state.dart';
import '../../common/action.dart';

/// `sys/backups/<id>` ▸ `send {link, connection, path}` (ADR 0048 §3.4):
/// the broker writes the backup through a file-store link the host listed,
/// into the host's folder. It answers once the link took the upload; the
/// rest shows in `send_status`, `send_progress`, `send_error` and
/// `sent_to` of the backup. An existing name is refused, never replaced.
/// A send its plan blocks is refused here before anything is sent.
class SendBackupAction extends Action with NonReentrant, WaitingAction {
  SendBackupAction(this.id);

  final String id;

  @override
  Future<AppState?> reduce() async {
    final key = '${site.root}/sys/backups/$id';
    final link = backups.sendLink;
    final connection = backups.sendConnection;
    final job = backups.table[id];
    // Decided here, whoever dispatched this: a backup with the keys is
    // never sent, and a send needs a link the host lists and a
    // connection (`backupJobPlan`).
    if (job == null ||
        link == null ||
        connection == null ||
        backupJobPlan(job).sendBlock != null) {
      throw stepBlockedOf(key, const .named('send'));
    }
    final path = backups.sendPath?.trim() ?? '';
    await invokeOne(
      deps.wyrm,
      key,
      'send',
      valueOf({
        'link': link,
        'connection': connection,
        if (path.isNotEmpty) 'path': path,
      }),
    );
    return null;
  }
}
