import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/backups/actions/download_backup_action.dart';
import 'package:business/redux/backups/actions/remove_backup_action.dart';
import 'package:business/redux/backups/actions/upload_restore_action.dart';
import 'package:flutter/foundation.dart';
import 'package:models/backup_job.dart';
import 'package:models/backup_kind.dart';

import 'files.dart';

// The steps of the backup dialog that need the system's file dialogs or
// a question to the user: each is one action, started by one dispatch
// (studio-rules §1, §9). In `app`: the file pickers are the app's.

/// *Download* of a kept backup: a folder is picked ([folderTitle] names
/// the picker), then the backup is read into it in parts. Nothing when the
/// user leaves the picker.
class DownloadBackupFileAction extends ReduxAction<AppState> {
  DownloadBackupFileAction(this.job, {required this.folderTitle});

  final BackupJob job;
  final String folderTitle;

  @override
  Future<AppState?> reduce() async {
    final file = await saveInto(
      job.name,
      fallback: job.kind == BackupKind.link
          ? 'backup.wyrm-link'
          : 'backup.wyrm-backup',
      dialogTitle: folderTitle,
    );
    if (file == null) {
      return null;
    }
    await dispatchAndWait(
      DownloadBackupAction(
        job.id,
        path: file.path,
        sha256: job.sha256,
        write: file.write,
        onDone: file.commit,
        onDiscard: file.discard,
      ),
    );
    return null;
  }
}

/// *Choose a file* of the restore: a `.wyrm-backup` is picked and sent to
/// the broker in parts. Nothing when the user leaves the picker.
class UploadRestoreFileAction extends ReduxAction<AppState> {
  @override
  Future<AppState?> reduce() async {
    final f = await pickFile(extensions: const ['wyrm-backup']);
    if (f == null) {
      return null;
    }
    try {
      await dispatchAndWait(
        UploadRestoreAction(name: f.name, size: f.size, read: f.read),
      );
    } finally {
      await f.close();
    }
    return null;
  }
}

/// *Remove* of a kept backup: the user is asked first ([ask], the
/// dialog's question), then the backup is removed and [removed] is told
/// (the dialog closes).
class RemoveBackupAskedAction extends ReduxAction<AppState> {
  RemoveBackupAskedAction(this.id, {required this.ask, required this.removed});

  final String id;
  final AsyncValueGetter<bool> ask;
  final VoidCallback removed;

  @override
  Future<AppState?> reduce() async {
    if (!await ask()) {
      return null;
    }
    final status = await dispatchAndWait(RemoveBackupAction(id));
    if (status.isCompletedOk) {
      removed();
    }
    return null;
  }
}
