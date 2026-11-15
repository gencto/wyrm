import 'package:app/app.dart';
import 'package:app/common/app_store.dart';
import 'package:app/navigation/app_router.dart';
import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/system/actions/clear_conns_action.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:models/access_tab.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'support/screen_app.dart';

/// *See my access* of a refusal of the user's rights (errors.md §3): the
/// error dialog closes, Access opens on Users with the user's own line
/// picked — one action. One test, because the app's router is built once
/// per test file.
void main() {
  testWidgets('See my access opens Access on the user', (t) async {
    final app = ScreenApp();
    await app.logIn(t);
    // the links are read again after clear_conns: a site with none
    app.api.children_['$plant/sys/links'] = [];
    app.api.errors['$plant/sys ▸ clear_conns'] = WyrmException.of(
      Status.permissionDenied,
      'needs config on sys',
    );
    app.put((s) => s.copyWith.access(tab: AccessTab.grants));
    createAppRouter(app.store);
    NavigateAction.setNavigatorKey(appRouter.navigatorKey);
    await t.pumpWidget(
      StoreProvider<AppState>(
        store: app.store,
        child: AppStore(
          store: app.store,
          child: AppConnector(routerConfig: appRouter.config()),
        ),
      ),
    );
    await app.settle(t);
    await app.go(t, const FlowsRoute());
    await t.runAsync(() => app.store.dispatchAndWait(ClearConnsAction()));
    await app.settle(t);
    expect(find.text(S.current.errSeeAccess), findsOneWidget);

    await t.tap(find.text(S.current.errSeeAccess));
    await app.settle(t);
    expect(app.top, AccessRoute.name);
    expect(app.store.state.access.tab, AccessTab.users);
    expect(app.store.state.access.selected, app.store.state.site.user);
    await app.leave(t);
  });
}
