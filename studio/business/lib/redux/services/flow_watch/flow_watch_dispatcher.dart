import 'package:async_redux/async_redux.dart';
import 'package:models/live_value.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../app_state.dart';
import '../../flow_editor/actions/reload_redeployed_flow_action.dart';
import '../../flow_editor/actions/set_flow_ports_action.dart';
import '../../flow_editor/actions/set_watch_refused_action.dart';
import 'flow_watch.dart';

/// One [SetFlowPortsAction] per batch of the flow's live values; a refusal
/// and a redeploy reach the editor's state.
class FlowWatchDispatcher implements FlowWatchServiceListener {
  FlowWatchDispatcher({required this._store});

  final Store<AppState> _store;

  @override
  void onPorts(Map<String, LiveValue> changed, {required bool reset}) =>
      _store.dispatchSync(SetFlowPortsAction(changed, reset: reset));

  @override
  void onRefused(Status? status) =>
      _store.dispatchSync(SetWatchRefusedAction(status));

  /// A stream listener does not wait (studio-rules §1): the flow on screen
  /// is read again unless its draft differs (`ReloadRedeployedFlowAction`).
  @override
  void onRedeployed(int? version) =>
      _store.dispatch(ReloadRedeployedFlowAction());
}
