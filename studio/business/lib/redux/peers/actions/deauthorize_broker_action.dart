import '../../app_state.dart';
import '../../common/action.dart';
import '../../links/actions/deauthorize_link_action.dart';
import 'retrieve_peers_action.dart';

/// A broker below loses its rights (`sys/quarantine ▸ deauthorize`), then
/// the peers are read again: one intent.
class DeauthorizeBrokerAction extends Action {
  DeauthorizeBrokerAction(this.name);

  /// The broker's site.
  final String name;

  @override
  Future<AppState?> reduce() async {
    final done = await dispatchAndWait(DeauthorizeLinkAction(name));
    if (done.isCompletedOk) {
      await dispatchAndWait(RetrievePeersAction());
    }
    return null;
  }
}
