import 'package:async_redux/async_redux.dart';
import 'package:models/live_value.dart';

import '../../app_state.dart';
import '../../live/actions/set_live_values_action.dart';
import 'live_values.dart';

/// One [SetLiveValuesAction] per batch.
class LiveValuesDispatcher implements LiveValuesServiceListener {
  LiveValuesDispatcher({required this._store});

  final Store<AppState> _store;

  @override
  void onValues(Map<String, LiveValue?> changed) =>
      _store.dispatchSync(SetLiveValuesAction(changed));
}
