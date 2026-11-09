import 'package:async_redux/async_redux.dart';
import 'package:models/live_value.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../app_state.dart';
import '../../flow_editor/actions/set_flow_preview_action.dart';
import '../../flow_editor/actions/set_preview_error_action.dart';
import '../../flow_editor/actions/set_preview_off_action.dart';
import 'flow_preview.dart';

/// One [SetFlowPreviewAction] per batch of the draft's live values; the
/// compiler's refusal and a broker without the preview reach the editor's
/// state.
class FlowPreviewDispatcher implements FlowPreviewServiceListener {
  FlowPreviewDispatcher({required this._store});

  final Store<AppState> _store;

  @override
  void onValues(
    Map<String, LiveValue> ports,
    Map<String, LiveValue> sinks, {
    required bool reset,
  }) => _store.dispatchSync(SetFlowPreviewAction(ports, sinks, reset: reset));

  @override
  void onInvalid(String? message) =>
      _store.dispatchSync(SetPreviewErrorAction(message));

  @override
  void onOff(Status? status) =>
      _store.dispatchSync(SetPreviewOffAction(status?.wireName));
}
