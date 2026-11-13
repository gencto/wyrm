import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:async_redux/async_redux.dart';
import 'package:models/install_source.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../../wyrm/failures.dart';
import '../../../wyrm/mappers/values.dart';
import '../../../wyrm/transfer.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import '../../links/actions/retrieve_links_action.dart';

/// Add a link ▸ From backup (ADR 0048 §3.5): the `.wyrm-link` goes to
/// `wy/<broker>/sys/backups` in parts (`restore_begin`, `restore_part`),
/// then `wy/<broker>/sys/links` ▸ `install_backup {upload, id, accept,
/// passphrase}` → `{success, message}`, kept verbatim: `phase` is `done` or
/// `failed`. Without `accept`, a link with grants or a network allowlist is
/// not installed and the message lists them.
///
/// [passphrase] comes from the wizard's own state and goes nowhere else.
class InstallBackupAction extends Action with NonReentrant, WaitingAction {
  InstallBackupAction({this.passphrase});

  final String? passphrase;

  @override
  Future<AppState?> reduce() async {
    final li = linkInstall;
    final broker = li.broker ?? site.viewed;
    final source = li.source;
    final name = li.name;
    if (broker == null ||
        name == null ||
        name.isEmpty ||
        source is! InstallSourceBackup) {
      return null;
    }
    final bytes = source.bytes;
    dispatchSync(_Phase(bytes.length, 0));
    String? message;
    var success = false;
    try {
      final upload = await uploadParts(
        deps.wyrm,
        'wy/$broker/sys/backups',
        size: bytes.length,
        read: (offset, length) async => Uint8List.sublistView(
          bytes,
          offset,
          math.min(bytes.length, offset + length),
        ),
        onProgress: (sent) => dispatchSync(_Phase(bytes.length, sent)),
      );
      final rows = await deps.wyrm
          .invoke(
            'wy/$broker/sys/links',
            'install_backup',
            Value.from({
              'upload': upload,
              'id': name,
              if (li.acceptRights) 'accept': true,
              if (passphrase case final p? when p.isNotEmpty) 'passphrase': p,
            }),
          )
          .toList();
      final last = rows.isEmpty ? const VNull() : rows.last;
      success = boolean(last['success']) ?? last is! VNull;
      message = str(last['message']) ?? (success ? null : text(last));
    } on WyrmException catch (e) {
      message = '${e.status.name}: ${e.message}';
    } on StudioException catch (e) {
      // A refused part of the upload: the broker's own words.
      message = e.error.message;
    }
    if (success) {
      unawaited(dispatchAndWait(RetrieveLinksAction()));
    }
    return state.copyWith.linkInstall(
      phase: success ? 'done' : 'failed',
      message: message,
      step: 4,
    );
  }
}

class _Phase extends Action {
  _Phase(this.size, this.sent);

  final int size;
  final int sent;

  @override
  AppState reduce() => state.copyWith.linkInstall(
    phase: 'installing',
    message: null,
    refusedField: null,
    refusedSaid: null,
    backupSize: size,
    uploaded: sent,
  );
}
