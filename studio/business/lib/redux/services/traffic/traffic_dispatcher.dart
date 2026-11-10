import 'package:async_redux/async_redux.dart';

import '../../app_state.dart';
import '../../system/actions/sample_traffic_action.dart';
import 'traffic.dart';

class TrafficDispatcher implements TrafficServiceListener {
  TrafficDispatcher({required this._store});

  final Store<AppState> _store;

  @override
  void onTick() => _store.dispatchSync(SampleTrafficAction());
}
