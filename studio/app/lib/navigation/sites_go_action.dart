import 'package:business/redux/app_state.dart';
import 'package:business/redux/common/action.dart';
import 'package:business/redux/links/actions/set_tab_action.dart';
import 'package:business/redux/site/actions/switch_site_action.dart';
import 'package:models/links_tab.dart';
import 'package:ui/pages/sites_page.dart';

import 'app_router.dart';
import 'explore_action.dart';
import 'go_after_action.dart';

/// Where a link of Sites leads ([go]), at what is picked: Links at its tab,
/// the picked site's tree in Explorer (it becomes the site viewed), or the
/// picked platform's node in Explorer. One intent, one dispatch.
class SitesGoAction extends Action {
  SitesGoAction(this.go);

  final SiteGo go;

  @override
  Future<AppState?> reduce() async {
    final name = peers.sitePicked.name;
    await dispatchAndWait(switch (go) {
      SiteGo.quarantine => GoAfterAction(const LinksRoute(), [
        SetTabAction(LinksTab.quarantine),
      ]),
      SiteGo.remote => GoAfterAction(const LinksRoute(), [
        SetTabAction(LinksTab.remote),
      ]),
      SiteGo.tree => GoAfterAction(const ExplorerRoute(), [
        SwitchSiteAction(name),
      ]),
      SiteGo.platform => ExploreAction('${site.root}/downstream/uplink/$name'),
    });
    return null;
  }
}
