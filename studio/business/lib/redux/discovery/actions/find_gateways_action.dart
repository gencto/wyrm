import '../../../wyrm/discovery.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import 'begin_find_action.dart';

/// *Find on this network* and *Look again* (ADR 0050 §2.3,
/// docs/design/specs/unlock-discover.md §4): browses `_wyrm._tcp` for 8 s.
/// `GatewayBrowserService` hands each service it resolves to
/// `CheckFoundGatewayAction`, so rows appear as they answer; this action
/// ends with the browse. Finding never means trusting.
class FindGatewaysAction extends Action {
  @override
  Future<AppState?> reduce() async {
    final net = await deps.gatewayInfo.localNetwork();
    dispatchSync(BeginFindAction(network: net?.interface, subnet: net?.subnet));
    final scan = discovery.scan;
    await deps.gatewayBrowser.browse(scan);
    // A newer search, or a closed panel, owns the state now.
    if (discovery.scan != scan) {
      return null;
    }
    return state.copyWith.discovery(scanning: false, ended: true);
  }
}

/// The local network as the panel names it: `en0 (10.0.7.0/24)`.
String? networkLabel(LocalNetwork? net) =>
    net == null ? null : '${net.interface} (${net.subnet})';
