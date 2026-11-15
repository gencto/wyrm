import '../../app_state.dart';
import '../../common/action.dart';
import '../../links/actions/retrieve_links_action.dart';
import '../../live/actions/watch_keys_action.dart';
import '../../quarantine/actions/retrieve_quarantine_action.dart';
import 'retrieve_peers_action.dart';

/// Sites comes on screen: it watches the values it shows
/// (`peers.sitesKeys`) and reads the links, the quarantine and the peers,
/// in that order (the peers' devices are the external links).
///
/// Rebuilds, decided: the watch changes nothing Sites draws before the
/// values come (`notify: false`); each read notifies for what it changes.
/// Changes no state itself.
class ShowSitesAction extends Action {
  @override
  Future<AppState?> reduce() async {
    dispatchSync(WatchKeysAction(peers.sitesKeys), notify: false);
    await dispatchAndWait(RetrieveLinksAction());
    await dispatchAndWait(RetrieveQuarantineAction());
    await dispatchAndWait(RetrievePeersAction());
    return null;
  }
}
