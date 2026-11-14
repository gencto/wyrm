import 'package:wyrm_client/wyrm_client.dart';

import '../../../wyrm/calls.dart';
import '../../../wyrm/mappers/values.dart';
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
///    state before the restore is then in place). Neither: `stage:
///    unknown`, said as it is.
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

  bool get _open => backups.stage == 'restarting';

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
      return _open ? state.copyWith.backups(stage: 'lost') : null;
    }
    // The start that applied it writes its record once the stores opened.
    Value? found;
    for (var i = 0; i < 20 && found == null && _open; i++) {
      try {
        final rows = await askOne(
          deps.wyrm,
          '$root/sys/audit',
          'tail',
          valueOf({'n': 50}),
        );
        if (rows case VArray(:final v)) {
          for (final r in v.reversed) {
            final op = str(r['op']);
            final t = integer(r['t']) ?? 0;
            // `t` is unix seconds or finer: only records of this restore.
            final seconds = t > 100000000000
                ? t ~/ (t > 100000000000000 ? 1000000 : 1000)
                : t;
            if ((op == 'restore_applied' || op == 'restore_failed') &&
                seconds >= since) {
              found = r;
              break;
            }
          }
        }
      } on Object {
        // The broker is still coming up: asked again.
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
      stage: switch (str(found?['op'])) {
        'restore_applied' => 'applied',
        'restore_failed' => 'not-applied',
        _ => 'unknown',
      },
      result: str(found?['detail']) ?? backups.result,
    );
  }
}
