import '../../app_state.dart';
import '../../common/action.dart';
import '../../login/actions/probe_gateway_action.dart';
import 'trust_gateway_action.dart';

/// *It matches · trust `<site>`* on the trust card (ADR 0050 §2.3): the CA
/// of the pending row is pinned, then the gateway is probed under the new
/// pin. A refused trust leaves the card with its reason and probes nothing.
class ConfirmTrustAction extends Action {
  @override
  Future<AppState?> reduce() async {
    final pending = discovery.trustPending;
    if (pending == null) {
      return null;
    }
    final status = await dispatchAndWait(TrustGatewayAction(pending));
    if (status.isCompletedOk && discovery.trustPending == null) {
      await dispatchAndWait(ProbeGatewayAction());
    }
    return null;
  }
}
