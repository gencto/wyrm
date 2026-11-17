import 'package:models/error_kind.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../../wyrm/failures.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import '../../nodes/actions/retry_read_action.dart';
import '../../problems/actions/add_problem_action.dart';
import 'set_read_failed_action.dart';

/// The subscription of [key] failed with [error]: the `read failed` mark on
/// its row and a quiet problem (docs/design/specs/errors.md §4), in one
/// state. A stream that lost its broker is one problem per site (its toast
/// stays until values come again), not one per key. A key the user may not
/// read is a line in Problems and the mark on its row, without a toast: a
/// folder of such points must not raise fifty.
class ReadFailedAction extends Action {
  ReadFailedAction(this.key, this.error);

  final String key;
  final Object error;

  @override
  AppState reduce() {
    final e = switch (error) {
      final WyrmException w => refusalOf(
        w,
        key: key,
        call: const .known(.subscribe),
      ),
      _ => faultOf(
        error,
        null,
        step: const .known(.subscribe),
      ).copyWith(key: key),
    };
    dispatchSync(
      SetReadFailedAction(key, e.status?.name ?? e.report?.type ?? 'failed'),
      notify: false,
    );
    final lost = e.kind == ErrorKind.reach && e.site != null;
    dispatchSync(
      AddProblemAction(
        lost
            ? e.copyWith(key: 'wy/${e.site}/**', stream: e.site, quiet: true)
            : e.copyWith(
                quiet: e.kind != ErrorKind.rights,
                retry: () => RetryReadAction(key),
              ),
      ),
      notify: false,
    );
    return state;
  }
}
