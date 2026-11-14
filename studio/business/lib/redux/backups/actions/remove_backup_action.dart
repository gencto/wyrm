import 'package:async_redux/async_redux.dart';

import '../../../wyrm/calls.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import 'retrieve_backups_action.dart';

/// `sys/backups/<id>` ▸ `remove` (config). A backup that is being made or
/// sent answers `busy`.
class RemoveBackupAction extends Action with NonReentrant, WaitingAction {
  RemoveBackupAction(this.id);

  final String id;

  @override
  Action reload() => RetrieveBackupsAction();

  @override
  Future<AppState?> reduce() async {
    await invokeAll(deps.wyrm, '${site.root}/sys/backups/$id', 'remove');
    await dispatchAndWait(RetrieveBackupsAction(quiet: true));
    return null;
  }
}
