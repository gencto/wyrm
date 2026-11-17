import '../../app_state.dart';
import '../../common/action.dart';
import '../../links/actions/retrieve_links_action.dart';
import 'view_site_action.dart';

/// The person picks [target] in the site switcher (or a search result on
/// it): the site is shown at once ([ViewSiteAction]: every screen's tables
/// emptied, the lists and values moved), then its links are read, the
/// last step of the switch. It changes no state itself (`null`).
class SwitchSiteAction extends Action {
  SwitchSiteAction(this.target);

  final String target;

  @override
  Future<AppState?> reduce() async {
    if (target == site.viewed) {
      return null;
    }
    dispatchSync(ViewSiteAction(target));
    await dispatchAndWait(RetrieveLinksAction());
    return null;
  }
}
