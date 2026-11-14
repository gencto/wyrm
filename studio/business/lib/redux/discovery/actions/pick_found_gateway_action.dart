import '../../app_state.dart';
import '../../common/action.dart';
import 'trust_gateway_action.dart';

/// A found row was picked: the gateway field gets its URL and its standby
/// (`main, standby`), and the status line says where it came from. A row
/// whose CA this computer does not know opens the trust card first; one
/// signed by a CA already pinned for another site is trusted at once, as
/// the person checked that CA before (a refusal opens the card with the
/// reason). A row that cannot be used does nothing.
class PickFoundGatewayAction extends Action {
  PickFoundGatewayAction(this.found);

  /// The site of the row (`discovery.found` key).
  final String found;

  @override
  Future<AppState?> reduce() async {
    final row = discovery.found[found];
    final url = row?.url;
    if (row == null || url == null || row.problem != null) {
      return null;
    }
    if (!row.known && row.knownAs != null) {
      await dispatchAndWait(TrustGatewayAction(found));
    }
    final known =
        row.known || (row.knownAs != null && discovery.trustPending == null);
    return state.copyWith(
      login: state.login.copyWith(
        gateway: [url, ?row.standby].join(', '),
        failure: null,
        reason: null,
      ),
      discovery: state.discovery.copyWith(
        picked: found,
        trustPending: known ? null : found,
        // A refusal of the trust just tried stays on the card.
        trustRefused: row.knownAs != null ? discovery.trustRefused : null,
      ),
    );
  }
}
