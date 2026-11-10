import 'package:async_redux/async_redux.dart';
import 'package:models/error_kind.dart';
import 'package:models/live_value.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../../wyrm/failures.dart';
import '../../app_state.dart';
import '../../live/actions/set_live_values_action.dart';
import '../../live/actions/set_read_failed_action.dart';
import '../../problems/actions/add_problem_action.dart';
import '../../problems/actions/resolve_stream_action.dart';
import 'live_values.dart';

/// One [SetLiveValuesAction] per batch; a failed subscription becomes the
/// row's `read failed` mark and a quiet problem
/// (docs/design/specs/errors.md §4).
class LiveValuesDispatcher implements LiveValuesServiceListener {
  LiveValuesDispatcher({required this._store});

  final Store<AppState> _store;

  @override
  void onValues(Map<String, LiveValue?> changed) {
    _store.dispatchSync(SetLiveValuesAction(changed));
    // Values from a site whose stream was down: it is back.
    final down = {
      for (final e in _store.state.problems.items)
        if (e.stream case final s?
            when _store.state.problems.toasts.contains(e.id))
          s,
    };
    if (down.isEmpty) {
      return;
    }
    for (final site in {for (final k in changed.keys) ?siteOf(k)}) {
      if (down.contains(site)) {
        _store.dispatchSync(ResolveStreamAction(site));
      }
    }
  }

  @override
  void onError(String key, Object error) {
    final e = switch (error) {
      final WyrmException w => refusalOf(w, key: key, call: 'subscribe'),
      _ => faultOf(error, null, step: 'subscribe').copyWith(key: key),
    };
    _store.dispatchSync(
      SetReadFailedAction(key, e.status?.name ?? e.report?.type ?? 'failed'),
    );
    // A stream that lost its broker is one problem per site (its toast
    // stays until values come again), not one per key. A key the user may
    // not read is a line in Problems and the mark on its row, without a
    // toast: a folder of such points must not raise fifty.
    final lost = e.kind == ErrorKind.reach && e.site != null;
    _store.dispatchSync(
      AddProblemAction(
        lost
            ? e.copyWith(
                key: 'wy/${e.site}/**',
                stream: e.site,
                quiet: true,
              )
            : e.copyWith(quiet: e.kind != ErrorKind.rights),
      ),
    );
  }
}
