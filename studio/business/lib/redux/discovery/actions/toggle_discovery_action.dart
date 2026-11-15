import '../../app_state.dart';
import '../../common/action.dart';
import 'close_discovery_action.dart';
import 'find_gateways_action.dart';

/// *Find on this network* beside the gateway field (unlock-discover.md
/// §4): opens the panel and browses, or closes it while it is open.
class ToggleDiscoveryAction extends Action {
  @override
  Future<AppState?> reduce() async {
    if (discovery.open) {
      dispatchSync(CloseDiscoveryAction());
    } else {
      await dispatchAndWait(FindGatewaysAction());
    }
    return null;
  }
}
