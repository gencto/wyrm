import 'package:app/connectors/log_in_page_connector.dart';
import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/wyrm/session.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/buttons/recent_chip.dart';
import 'package:ui/theme/common.dart';

import '../../business/test/support/fake_wyrm.dart';

/// docs/design/specs/login.md §3.2 "Gateway labels", through the connector:
/// five gateways on one computer are five chips told apart by their port,
/// and the status line names the field's gateway the same way.
void main() {
  setUpAll(() => S.load(const Locale('en')));

  const ports = [8444, 8445, 8446, 18448, 18449];

  testWidgets('five recent gateways on 127.0.0.1: one label per port', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = fakeStore(
      login: FakeLogin(answer: const GatewayProbe.noAnswer('timed out')),
      initial: AppState.initial().copyWith.login(
        gateway: 'http://127.0.0.1:8446',
        recent: [for (final p in ports) 'http://127.0.0.1:$p'].lock,
      ),
    );
    await tester.pumpWidget(
      StoreProvider<AppState>(
        store: store,
        child: MaterialApp(
          theme: darkTheme(),
          localizationsDelegates: const [S.delegate],
          home: const LogInPageConnector(),
        ),
      ),
    );
    // the probe on open answers at once; the page's loops never settle
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final chips = tester.widgetList<RecentChip>(find.byType(RecentChip));
    expect(
      [for (final c in chips) c.vm.label],
      [
        for (final p in ports) '127.0.0.1:$p',
      ],
    );
    expect(find.text('No answer from 127.0.0.1:8446'), findsOneWidget);
  });
}
