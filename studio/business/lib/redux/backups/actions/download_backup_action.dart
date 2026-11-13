import 'package:async_redux/async_redux.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:models/error_kind.dart';
import 'package:models/studio_error.dart';

import '../../../wyrm/failures.dart';
import '../../../wyrm/transfer.dart';
import '../../app_state.dart';
import '../../common/action.dart';

/// Downloads a kept backup in parts (`sys/backups/<id>` ▸ `download_part
/// {offset, len}` until `eof`): each part goes to [write] (the file the
/// user chose) before the next is asked for, and `backups.downloaded`
/// follows. When the last part is in, the SHA-256 of what was read is
/// compared with [sha256] (the backup's `sha256` value): a file that
/// differs is an error, never a success.
///
/// *Cancel* clears `backups.downloading`; the action then stops before its
/// next part and [onCancel] removes what was written.
class DownloadBackupAction extends Action with NonReentrant, WaitingAction {
  DownloadBackupAction(
    this.id, {
    required this.write,
    required this.path,
    this.sha256 = '',
    this.part = downloadPart,
    this.onDone,
    this.onCancel,
  });

  final String id;
  final PartWriter write;

  /// Where the file goes, as the user reads it.
  final String path;
  final String sha256;
  final int part;

  /// Closes the file.
  final Future<void> Function()? onDone;

  /// Closes and removes the file of a download that did not end.
  final Future<void> Function()? onCancel;

  @override
  Future<AppState?> reduce() async {
    final key = '${site.root}/sys/backups/$id';
    dispatchSync(_Progress(id, 0, null));
    final digest = _Digest();
    final hash = crypto.sha256.startChunkedConversion(digest);
    try {
      await downloadParts(
        deps.wyrm,
        key,
        part: part,
        cancelled: () => backups.downloading != id,
        onProgress: (done, _) => dispatchSync(_Progress(id, done, null)),
        write: (data) async {
          hash.add(data);
          await write(data);
        },
      );
      hash.close();
      if (sha256.isNotEmpty && digest.value != sha256) {
        throw StudioException(
          StudioError(
            kind: ErrorKind.broker,
            message:
                'The file that arrived is not the backup: SHA-256 '
                '${digest.value}, the broker says $sha256.',
            key: key,
            call: 'download_part',
            site: siteOf(key),
          ),
        );
      }
      await onDone?.call();
    } on TransferCancelled {
      await onCancel?.call();
      return state.copyWith.backups(downloading: null, downloaded: 0);
    } on Object {
      await onCancel?.call();
      dispatchSync(_Progress(null, 0, null));
      rethrow;
    }
    return state.copyWith.backups(downloading: null, savedTo: path);
  }
}

class _Digest implements Sink<crypto.Digest> {
  var value = '';

  @override
  void add(crypto.Digest data) => value = data.toString();

  @override
  void close() {}
}

class _Progress extends Action {
  _Progress(this.id, this.done, this.savedTo);

  final String? id;
  final int done;
  final String? savedTo;

  /// The first one marks the download; a later one only counts, so it
  /// never brings back a download that was cancelled meanwhile.
  @override
  AppState? reduce() => done == 0 || id == null
      ? state.copyWith.backups(
          downloading: id,
          downloaded: done,
          savedTo: savedTo,
        )
      : (backups.downloading == id
            ? state.copyWith.backups(downloaded: done)
            : null);
}
