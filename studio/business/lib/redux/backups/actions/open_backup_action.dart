import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/backup_place.dart';
import 'package:models/backup_section.dart';
import 'package:models/backup_stage.dart';
import 'package:models/link_info.dart';
import 'package:models/restore_mode.dart';

import '../../app_state.dart';
import '../../common/action.dart';

/// Opens the backup dialog (boards `Backup`, `LinkBackup`, `BackupRestore`):
/// of the broker, of one [link], or the restore of a file. Every answer of
/// an earlier dialog is cleared; a passphrase is never here (it stays in
/// the dialog's own state and goes to the broker as an action argument).
///
/// A broker backup starts with every section but `keys` (which needs a
/// passphrase); a link backup with settings, private data and, for a link
/// that runs a package, the package.
class OpenBackupAction extends Action {
  OpenBackupAction({this.link, this.restore = false, this.job});

  final String? link;
  final bool restore;

  /// Opens on a backup that exists: its progress or its result.
  final String? job;

  @override
  AppState reduce() => state.copyWith.backups(
    opening: backups.opening + 1,
    stage: restore
        ? BackupStage.restore
        : (job != null
              ? BackupStage.job
              : (link == null ? BackupStage.choose : BackupStage.link)),
    link: link,
    job: job,
    chosen: restore
        ? const ISetConst({})
        : (link == null
              ? backups.sections.where((s) => s != BackupSection.keys).toISet()
              : {
                  BackupSection.settings,
                  BackupSection.data,
                  // A built-in driver has no package to carry.
                  if (links.table[link ?? '']?.runsPackage ?? false)
                    BackupSection.package,
                }.toISet()),
    historyDays: link == null && !restore ? 30 : null,
    offLinks: const ISetConst({}),
    where: BackupPlace.computer,
    sendLink: null,
    sendConnection: null,
    sendPath: null,
    connections: const IListConst([]),
    estimate: const IMapConst({}),
    upload: null,
    uploadName: null,
    uploadSize: 0,
    uploaded: 0,
    check: null,
    mode: RestoreMode.add,
    staged: const IListConst([]),
    applySent: false,
    replaceKeys: false,
    acceptRights: false,
    result: null,
  );
}
