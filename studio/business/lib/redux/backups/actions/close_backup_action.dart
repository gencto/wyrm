import '../../../wyrm/transfer.dart';
import '../../app_state.dart';
import '../../common/action.dart';

/// Closes the backup dialog. A backup that is being made goes on in the
/// broker and stays in the list; an upload of a restore that was not
/// applied is dropped on the broker (`restore_abort`). A download that
/// runs goes on.
class CloseBackupAction extends Action {
  @override
  Future<AppState?> reduce() async {
    final upload = backups.upload;
    final applied = backups.result != null;
    final next = state.copyWith.backups(
      stage: null,
      link: null,
      job: null,
      upload: null,
      uploadName: null,
      uploadSize: 0,
      uploaded: 0,
      check: null,
      result: null,
    );
    if (upload != null && !applied && site.root != null) {
      await abortUpload(deps.wyrm, '${site.root}/sys/backups', upload);
    }
    return next;
  }
}
