import 'package:app/navigation/app_router.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:models/links_tab.dart';
import 'package:ui/pages/sites_page.dart';

import 'support/screen_app.dart';
import 'support/sites_fixture.dart';

/// Where Sites' links lead, in Studio's own shell and router: Review and
/// the inspector's rows open Links at its tab, a site below or a platform
/// opens Explorer. One test, because the app's router is built once per
/// test file.
void main() {
  testWidgets('each link opens its workspace at what it names', (t) async {
    final app = ScreenApp();
    sitesBroker(app.api);
    await app.logIn(t);
    app.put(withSites);
    await app.pumpInStudio(t, const SitesRoute());
    await app.settle(t, rounds: 50);
    expect(app.top, SitesRoute.name);

    Finder onSites(String text) =>
        find.descendant(of: find.byType(SitesPage), matching: find.text(text));

    Future<void> tap(String text) async {
      // the last: an action's code comes after a fact of the same text
      await t.ensureVisible(onSites(text).last);
      await t.tap(onSites(text).last);
      await app.settle(t, rounds: 50);
    }

    Future<void> back({String? pick}) async {
      await app.go(t, const SitesRoute());
      await app.settle(t, rounds: 50);
      app.put((s) => s.copyWith.peers(selectedPeer: pick));
      await app.settle(t);
    }

    // the waiting banner
    await tap('Review');
    expect(app.top, LinksRoute.name);
    expect(app.store.state.links.tab, LinksTab.quarantine);

    // this broker: Quarantine and admission
    await back();
    app.put((s) => s.copyWith.links(tab: LinksTab.local));
    await tap('enable_quarantine');
    expect(app.top, LinksRoute.name);
    expect(app.store.state.links.tab, LinksTab.quarantine);

    // a link waiting: Decide in Links
    await back(pick: 'waiting:field-x');
    app.put((s) => s.copyWith.links(tab: LinksTab.local));
    await tap('sys/quarantine');
    expect(app.top, LinksRoute.name);
    expect(app.store.state.links.tab, LinksTab.quarantine);

    // a link on another device: Open in Links
    await back(pick: 'device:field-gw');
    await tap('sys/links');
    expect(app.top, LinksRoute.name);
    expect(app.store.state.links.tab, LinksTab.remote);

    // a platform: Open in Explorer, at its node
    await back(pick: 'platform:mqtt-cloud');
    await tap('downstream/uplink');
    expect(app.top, ExplorerRoute.name);
    expect(
      app.store.state.nodes.selectedNode,
      '$plant/downstream/uplink/mqtt-cloud',
    );

    // a broker below: Open its tree, its site viewed
    await back(pick: 'downstream:line1');
    await tap('wy/line1');
    expect(app.top, ExplorerRoute.name);
    expect(app.store.state.site.current, 'line1');
    await app.leave(t);
  });
}
