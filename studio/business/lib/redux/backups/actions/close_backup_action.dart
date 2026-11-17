import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/backup_stage.dart';

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
    // past the restore form the broker has applied or staged the upload
    final applied = backups.stage != BackupStage.restore;
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
      staged: const IListConst([]),
    );
    if (upload != null && !applied && site.root != null) {
      await abortUpload(deps.wyrm, '${site.root}/sys/backups', upload);
    }
    return next;
  }
}
