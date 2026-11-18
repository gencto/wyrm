import 'dart:async';

import 'package:models/backup_stage.dart';
import 'package:models/restore_end.dart';
import 'package:models/restore_record.dart';

import '../../../wyrm/calls.dart';
import '../../../wyrm/decode/restore.dart';
import '../../../wyrm/failures.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import 'retrieve_backups_action.dart';

/// Follows a restore with `mode: replace` to its end (ADR 0048 §3.6): the
/// broker answered and stops, the next start applies the staged sections.
///
/// 1. It waits for the gateway to go away ([lose]; a broker that restarted
///    faster than the socket noticed is taken as gone).
/// 2. It waits for the gateway to come back ([back]). When it does not, the
///    dialog says so (`stage: lost`): with other keys in place the session
///    of this Studio is no longer the site's, and the user logs in again.
/// 3. It reads what the start wrote in the audit (`sys/audit` ▸ `tail`):
///    `restore_applied`, or `restore_failed` with the broker's reason (the
///    state before the restore is then in place). Neither, or an audit
///    this client cannot read (logged with its field): `stage: unknown`,
///    said as it is.
///
/// Closing the dialog ends the watch; the restore goes on in the broker.
class FollowRestoreAction extends Action with WaitingAction {
  FollowRestoreAction({
    this.lose = const Duration(seconds: 20),
    this.back = const Duration(seconds: 180),
    this.step = const Duration(milliseconds: 500),
  }) : super(quiet: true);

  final Duration lose;
  final Duration back;
  final Duration step;

  bool get _open => backups.stage == BackupStage.restarting;

  Future<bool> _until(bool Function() test, Duration within) async {
    final end = DateTime.now().add(within);
    while (_open && !test()) {
      if (DateTime.now().isAfter(end)) {
        return false;
      }
      await Future<void>.delayed(step);
    }
    return _open;
  }

  @override
  Future<AppState?> reduce() async {
    final root = site.root;
    if (root == null || !_open) {
      return null;
    }
    final since = DateTime.now().millisecondsSinceEpoch ~/ 1000 - 5;
    await _until(() => !site.connected, lose);
    if (!_open) {
      return null;
    }
    if (!await _until(() => site.connected, back)) {
      return _open ? state.copyWith.backups(stage: BackupStage.lost) : null;
    }
    // The start that applied it writes its record once the stores opened.
    RestoreRecord? found;
    for (var i = 0; i < 20 && found == null && _open; i++) {
      try {
        final rows = await askOne(
          deps.wyrm,
          '$root/sys/audit',
          'tail',
          valueOf({'n': 50}),
        );
        // Only records of this restore, the newest one. Each row is
        // read on its own: one that cannot be read is logged with its
        // field and does not hide the others.
        found = [
          for (final r in restoreRecordsOf(rows)) ?r.orWarn('$root/sys/audit'),
        ].where((r) => r.seconds >= since).lastOrNull;
      } on StudioException {
        // The broker refused or did not answer: it is still coming up,
        // and is asked again. Anything else is a fault and leaves.
      } on TimeoutException {
        // No answer in time: asked again.
      }
      if (found == null) {
        await Future<void>.delayed(step);
      }
    }
    if (!_open) {
      return null;
    }
    await dispatchAndWait(RetrieveBackupsAction(quiet: true));
    if (!_open) {
      return null;
    }
    return state.copyWith.backups(
      stage: switch (found?.end) {
        RestoreEnd.applied => BackupStage.applied,
        RestoreEnd.failed => BackupStage.notApplied,
        null => BackupStage.unknown,
      },
      result: found?.detail ?? backups.result,
    );
  }
}
