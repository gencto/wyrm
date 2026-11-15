import '../../app_state.dart';
import '../../common/action.dart';
import '../../updates/actions/open_update_action.dart';

/// *Update to…* / *Update from file…* (the review) or *Versions and
/// restore points* ([follow]) of the link [id]: the update sheet of the
/// package it runs. Null for a built-in driver.
class OpenLinkUpdateAction extends Action {
  OpenLinkUpdateAction(this.id, {this.follow = false});

  final String id;
  final bool follow;

  @override
  AppState? reduce() {
    final l = links.table[id];
    final name = l == null ? null : packageOfLink(l);
    if (name == null) {
      return null;
    }
    dispatchSync(OpenUpdateAction(name, follow: follow));
    return null;
  }
}
