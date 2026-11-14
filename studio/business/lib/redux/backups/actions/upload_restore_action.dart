import 'package:async_redux/async_redux.dart';

import '../../../wyrm/transfer.dart';
import '../../app_state.dart';
import '../../common/action.dart';

/// Sends the `.wyrm-backup` the user picked to the broker in parts
/// (`sys/backups` ▸ `restore_begin`, `restore_part`); `backups.uploaded`
/// follows. Closing the dialog stops it and drops the upload.
class UploadRestoreAction extends Action with NonReentrant, WaitingAction {
  UploadRestoreAction({
    required this.name,
    required this.size,
    required this.read,
  });

  final String name;
  final int size;
  final PartReader read;

  @override
  Future<AppState?> reduce() async {
    dispatchSync(_Progress(name, size, 0));
    final String upload;
    try {
      upload = await uploadParts(
        deps.wyrm,
        '${site.root}/sys/backups',
        size: size,
        read: read,
        cancelled: () => backups.stage != 'restore',
        onProgress: (sent) => dispatchSync(_Progress(name, size, sent)),
      );
    } on TransferCancelled {
      return null;
    } on Object {
      // The dialog goes back to *Choose the file…*: another file, or the
      // same one again. The error leaves as every refusal does.
      dispatchSync(_Failed());
      rethrow;
    }
    return state.copyWith.backups(upload: upload, uploaded: size);
  }
}

class _Failed extends Action {
  @override
  AppState reduce() => state.copyWith.backups(
    upload: null,
    uploadName: null,
    uploadSize: 0,
    uploaded: 0,
  );
}

class _Progress extends Action {
  _Progress(this.name, this.size, this.sent);

  final String name;
  final int size;
  final int sent;

  @override
  AppState? reduce() => backups.stage != 'restore'
      ? null
      : state.copyWith.backups(
          uploadName: name,
          uploadSize: size,
          uploaded: sent,
        );
}
