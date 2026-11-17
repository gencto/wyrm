import 'package:async_redux/async_redux.dart';
import 'package:models/live_value.dart';

import '../../app_state.dart';
import '../../live/actions/apply_live_values_action.dart';
import '../../live/actions/read_failed_action.dart';
import 'live_values.dart';

/// One action per batch of values, up to five a second, and one per
/// failed subscription: each is one state, so a connector follows it once.
/// A stream listener does not wait (studio-rules §1): it dispatches and
/// returns.
class LiveValuesDispatcher implements LiveValuesServiceListener {
  LiveValuesDispatcher({required this._store});

  final Store<AppState> _store;

  @override
  void onValues(Map<String, LiveValue?> changed) =>
      _store.dispatch(ApplyLiveValuesAction(changed));

  @override
  void onError(String key, Object error) =>
      _store.dispatchSync(ReadFailedAction(key, error));
}
