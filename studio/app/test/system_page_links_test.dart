import 'package:app/navigation/app_router.dart';
import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:models/access_tab.dart';
import 'package:models/links_tab.dart';
import 'package:ui/pages/system_page.dart';

import 'support/system_app.dart';

/// Where System's links lead, in Studio's own shell and router: the tiles,
/// the attention panel, the banner and *Also broker settings*. One test,
/// because the app's router is built once per test file.
void main() {
  testWidgets('each link opens its workspace at what it names', (t) async {
    await S.load(const Locale('en'));
    final app = SystemApp(fixture: const SysFixture(standby: Standby.both));
    await app.pumpInStudio(t);
    expect(app.workspace, SystemRoute.name);

    Finder onSystem(String text) => find.descendant(
      of: find.byType(SystemPage),
      matching: find.text(text),
    );

    Future<void> tap(String text) async {
      await t.ensureVisible(onSystem(text).first);
      await t.tap(onSystem(text).first);
      await app.settle(t);
    }

    AppState s() => app.store.state;

    // the tiles
    await tap('Links connected');
    expect(app.workspace, LinksRoute.name);
    expect(s().links.tab, LinksTab.local);

    await app.toSystem(t);
    await tap('In quarantine');
    expect(app.workspace, LinksRoute.name);
    expect(s().links.tab, LinksTab.quarantine);

    await app.toSystem(t);
    await tap('Packages');
    expect(app.workspace, LinksRoute.name);
    expect(s().links.tab, LinksTab.local);

    await app.toSystem(t);
    await tap('Upstream');
    expect(app.workspace, SitesRoute.name);

    await app.toSystem(t);
    await tap('Downstream');
    expect(app.workspace, SitesRoute.name);

    await app.toSystem(t);
    await tap('data_dir');
    expect(app.workspace, HistoryRoute.name);

    await app.toSystem(t);
    await tap('ACL denials');
    expect(app.workspace, AccessRoute.name);
    expect(s().access.tab, AccessTab.audit);

    await app.toSystem(t);
    app.store.dispatchSync(_ResetAccess());
    await tap('Audit records');
    expect(app.workspace, AccessRoute.name);
    expect(s().access.tab, AccessTab.audit);

    // a tile with no destination leads nowhere
    await app.toSystem(t);
    await tap('Sessions');
    expect(app.workspace, SystemRoute.name);

    // the attention panel
    await tap('Standby is 1,240 records behind');
    expect(app.workspace, SystemRoute.name);
    expect(onSystem('Standby connected'), findsOneWidget);

    // the banner of Availability: the audit record of the fork
    app.store.dispatchSync(_ResetAccess());
    await tap('Open the audit record ›');
    expect(app.workspace, AccessRoute.name);
    expect(s().access.tab, AccessTab.audit);

    await app.toSystem(t);
    await tap('bacnet failed');
    expect(app.workspace, LinksRoute.name);
    expect(s().links.tab, LinksTab.local);
    expect(s().links.selectedLink, 'bacnet');

    await app.toSystem(t);
    await tap('field-gw waits in quarantine');
    expect(app.workspace, LinksRoute.name);
    expect(s().links.tab, LinksTab.quarantine);
    expect(s().quarantine.selectedEntry, 'field-gw');

    await app.toSystem(t);
    await tap('line2 waits for Authorize');
    expect(app.workspace, SitesRoute.name);
    expect(s().peers.selectedPeer, 'waiting:line2');

    // leaving System noted the ACL counter: as at an earlier visit again
    await app.toSystem(t);
    app.store
      ..dispatchSync(_ResetAccess())
      ..dispatchSync(_AclSeen(18000));
    await app.settle(t);
    await tap('ACL denials grew by 402');
    expect(app.workspace, AccessRoute.name);
    expect(s().access.tab, AccessTab.audit);

    // Also broker settings, on Maintenance
    await app.toSystem(t);
    await app.open(t, SysTab.maintenance);
    await tap('Admission of new links › Links › Quarantine');
    expect(app.workspace, LinksRoute.name);
    expect(s().links.tab, LinksTab.quarantine);

    await app.toSystem(t);
    await tap('Tokens for sites below › Sites');
    expect(app.workspace, SitesRoute.name);

    await app.toSystem(t);
    app.store.dispatchSync(_ResetAccess());
    await tap('Roles and grants › Access');
    expect(app.workspace, AccessRoute.name);
    expect(s().access.tab, AccessTab.users, reason: 'Access as it was');

    await app.toSystem(t);
    await tap('Retention and purge › History');
    expect(app.workspace, HistoryRoute.name);

    await app.toSystem(t);
    await tap('Design gallery');
    expect(app.workspace, GalleryRoute.name);

    await t.pumpWidget(const SizedBox());
    await app.settle(t);
  });
}

/// Access back on its first tab, so a link that opens Audit is seen to.
class _ResetAccess extends ReduxAction<AppState> {
  @override
  AppState reduce() => state.copyWith.access(tab: AccessTab.users);
}

/// The ACL counter as System saw it when it was last left.
class _AclSeen extends ReduxAction<AppState> {
  _AclSeen(this.seen);

  final int seen;

  @override
  AppState reduce() => state.copyWith.system(aclSeen: seen);
}
