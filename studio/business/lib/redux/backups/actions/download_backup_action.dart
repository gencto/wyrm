import 'package:async_redux/async_redux.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:models/error_kind.dart';
import 'package:models/studio_error.dart';

import '../../../wyrm/calls.dart';
import '../../../wyrm/failures.dart';
import '../../../wyrm/mappers/values.dart';
import '../../../wyrm/transfer.dart';
import '../../app_state.dart';
import '../../common/action.dart';

/// Downloads a kept backup in parts (`sys/backups/<id>` ▸ `download_part
/// {offset, len}` until `eof`): each part goes to [write] before the next
/// is asked for, and `backups.downloaded` follows.
///
/// A download is saved only when the SHA-256 of what arrived equals the
/// backup's `sha256`: [sha256] as the dialog has it, else the value read
/// from the broker here; a backup that shows none is an error, never a
/// file without a compared hash. The caller writes into a temporary file:
/// [onDone] (after the hash matched) gives it its name, [onDiscard]
/// removes it after a cancel, a refusal, a write error or a hash that
/// differs. Whatever way it ends, `backups.downloading` is cleared.
///
/// The saved path is kept by the backup's id (`backups.saved`): another
/// backup's dialog never shows it.
class DownloadBackupAction extends Action with NonReentrant, WaitingAction {
  DownloadBackupAction(
    this.id, {
    required this.write,
    required this.path,
    this.sha256 = '',
    this.part = downloadPart,
    this.onDone,
    this.onDiscard,
  });

  final String id;
  final PartWriter write;

  /// Where the file goes, as the user reads it.
  final String path;
  final String sha256;
  final int part;

  /// Closes the file and gives it its name.
  final Future<void> Function()? onDone;

  /// Closes and removes the file of a download that did not end well. It
  /// must not throw.
  final Future<void> Function()? onDiscard;

  StudioException _wrong(String key, String message) => StudioException(
    StudioError(
      kind: ErrorKind.broker,
      message: message,
      key: key,
      call: 'download_part',
      site: siteOf(key),
    ),
  );

  @override
  Future<AppState?> reduce() async {
    final key = '${site.root}/sys/backups/$id';
    dispatchSync(_Start(id));
    final digest = _Digest();
    final hash = crypto.sha256.startChunkedConversion(digest);
    var saved = false;
    try {
      final expected = sha256.isNotEmpty
          ? sha256
          : str(await readValue(deps.wyrm, '$key/sha256')) ?? '';
      if (expected.isEmpty) {
        throw _wrong(
          key,
          'The broker shows no SHA-256 of this backup, so what arrives '
          'cannot be checked. Nothing was saved.',
        );
      }
      await downloadParts(
        deps.wyrm,
        key,
        part: part,
        cancelled: () => backups.downloading != id,
        onProgress: (done, _) => dispatchSync(_Progress(id, done)),
        write: (data) async {
          hash.add(data);
          await write(data);
        },
      );
      hash.close();
      if (digest.value != expected) {
        throw _wrong(
          key,
          'The file that arrived is not the backup: SHA-256 '
          '${digest.value}, the broker says $expected. Nothing was saved.',
        );
      }
      await onDone?.call();
      saved = true;
    } on TransferCancelled {
      // The user stopped it: no error.
    } finally {
      if (!saved) {
        await onDiscard?.call();
      }
      dispatchSync(_End(id, saved ? path : null));
    }
    return null;
  }
}

class _Digest implements Sink<crypto.Digest> {
  var value = '';

  @override
  void add(crypto.Digest data) => value = data.toString();

  @override
  void close() {}
}

class _Start extends Action {
  _Start(this.id);

  final String id;

  @override
  AppState reduce() => state.copyWith.backups(
    downloading: id,
    downloaded: 0,
    saved: backups.saved.remove(id),
  );
}

/// Counts only while the download is still the one that runs, so it never
/// brings back a download that was cancelled meanwhile.
class _Progress extends Action {
  _Progress(this.id, this.done);

  final String id;
  final int done;

  @override
  AppState? reduce() => backups.downloading == id
      ? state.copyWith.backups(downloaded: done)
      : null;
}

class _End extends Action {
  _End(this.id, this.savedTo);

  final String id;
  final String? savedTo;

  @override
  AppState reduce() => state.copyWith.backups(
    downloading: backups.downloading == id ? null : backups.downloading,
    downloaded: savedTo == null ? 0 : backups.downloaded,
    saved: savedTo == null ? backups.saved : backups.saved.add(id, savedTo!),
  );
}
