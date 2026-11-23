import '../../../wyrm/flow_view/flow_view.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import '../../live/actions/unwatch_keys_action.dart';
import 'preview_flow_action.dart';
import 'watch_flow_action.dart';

/// The flow editor of route [routeId] closes: the keys it follows are let
/// go, and the flow's watch and the draft's preview stop.
class CloseFlowEditorAction extends Action {
  CloseFlowEditorAction(this.routeId);

  final String routeId;

  @override
  AppState? reduce() {
    dispatchSync(
      UnwatchKeysAction(flowViewOf(state, waiting, routeId).follow.watch),
      notify: false,
    );
    dispatchSync(WatchFlowAction(null), notify: false);
    dispatchSync(PreviewFlowAction(stop: true), notify: false);
    // One rebuild for the three.
    return state;
  }
}
