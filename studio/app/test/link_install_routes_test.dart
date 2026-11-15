import 'dart:async';

import 'package:app/common/app_store.dart';
import 'package:app/connectors/link_install_page_connector.dart';
import 'package:app/connectors/links_page_connector.dart';
import 'package:app/navigation/app_router.dart';
import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/buttons/button.dart';
import 'package:ui/theme/common.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'support/link_install_app.dart';

/// Add a link inside Studio's own shell and router (built once per file):
/// Links opens it, its close and *Back to Links* return, and *Open in
/// Explorer* returns with the new link's branch selected.
void main() {
  testWidgets('Links ▸ Add a link ▸ Install ▸ Open in Explorer', (t) async {
    await S.load(const Locale('en'));
    final app = LinkInstallApp();
    // what Links reads besides the links
    app.api
      ..children_['$sys/packages'] = const []
      ..children_['$sys/quarantine'] = const []
      ..errors['$sys/backups'] = WyrmException.of(Status.notFound, 'none');
    await app.pump(t);
    await t.pumpWidget(const SizedBox());
    final store = app.store;
    createAppRouter(store);
    await t.pumpWidget(
      StoreProvider<AppState>(
        store: store,
        child: AppStore(
          store: store,
          child: MaterialApp.router(
            routerConfig: appRouter.config(),
            theme: darkTheme(),
            localizationsDelegates: const [
              S.delegate,
              ...GlobalMaterialLocalizations.delegates,
            ],
          ),
        ),
      ),
    );
    await app.settle(t);
    unawaited(appRouter.navigate(const StudioRoute(children: [LinksRoute()])));
    await app.settle(t);
    expect(find.byType(LinksPageConnector), findsOneWidget);

    Future<void> press(String label) async {
      await t.tap(find.widgetWithText(Button, label).first);
      await app.settle(t);
    }

    // Add a link, then its close: back on Links
    await press(S.current.addALink);
    expect(find.byType(LinkInstallPageConnector), findsOneWidget);
    await t.tap(
      find
          .descendant(
            of: find.byType(LinkInstallPageConnector),
            matching: find.byType(IconButton),
          )
          .first,
    );
    await app.settle(t);
    expect(find.byType(LinkInstallPageConnector), findsNothing);
    expect(appRouter.topRoute.name, LinksRoute.name);

    // Back on the first step leaves too
    await press(S.current.addALink);
    await press(S.current.back);
    expect(find.byType(LinkInstallPageConnector), findsNothing);

    // Install, then Back to Links
    await press(S.current.addALink);
    await t.tap(find.text('Modbus').first);
    await app.settle(t);
    await press(S.current.continueLabel);
    await press(S.current.install);
    await press(S.current.backToLinks);
    expect(find.byType(LinkInstallPageConnector), findsNothing);
    expect(appRouter.topRoute.name, LinksRoute.name);

    // Install again, then Open in Explorer: the branch is selected
    await press(S.current.addALink);
    await t.tap(find.text('Mock').first);
    await app.settle(t);
    await press(S.current.continueLabel);
    await press(S.current.install);
    await press(S.current.openInExplorer);
    expect(find.byType(LinkInstallPageConnector), findsNothing);
    expect(store.state.nodes.selectedNode, 'wy/plant/downstream/mock');
    await t.pumpWidget(const SizedBox());
    await app.settle(t);
  });
}
