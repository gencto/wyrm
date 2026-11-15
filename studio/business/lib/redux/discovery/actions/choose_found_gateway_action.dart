import '../../app_state.dart';
import '../../common/action.dart';
import '../../login/actions/probe_gateway_action.dart';
import 'pick_found_gateway_action.dart';

/// A found row was tapped (unlock-discover.md §4): the row is picked; a
/// gateway whose CA is known is then probed. One whose CA waits for the
/// person's check is not reached before the trust (`ConfirmTrustAction`).
class ChooseFoundGatewayAction extends Action {
  ChooseFoundGatewayAction(this.found);

  /// The row's site (`discovery.found` key).
  final String found;

  @override
  Future<AppState?> reduce() async {
    final status = await dispatchAndWait(PickFoundGatewayAction(found));
    // The state now, after the pick: a trust may wait.
    if (status.isCompletedOk && discovery.trustPending == null) {
      await dispatchAndWait(ProbeGatewayAction());
    }
    return null;
  }
}
