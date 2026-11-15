import 'package:app/connectors/flows_page_connector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/pages/flows_page.dart';

import 'support/flows_fixture.dart';
import 'support/screen_app.dart';

/// Flows as the store makes it (studio-rules, step 1): every word in its
/// main states, in English and Ukrainian, and what each control does — read
/// from the state, not from which actions ran, so it holds before and after
/// the rewrite. Where its links lead: `flows_page_links_test.dart`.
void main() {
  final words = ScreenWords('flows');

  Future<ScreenApp> shown(
    WidgetTester t, {
    bool config = true,
    bool flows = true,
    String? selected,
    Locale locale = const Locale('en'),
  }) async {
    final app = ScreenApp(config: config);
    await app.logIn(t);
    if (flows) {
      app.put((s) => withFlows(s, selected: selected));
    }
    await app.pump(t, const FlowsPageConnector(), locale: locale);
    return app;
  }

  List<String> on(WidgetTester t, ScreenApp app) =>
      app.words(t, find.byType(FlowsPage));

  group('every word', () {
    testWidgets('the flows, none picked', (t) async {
      final app = await shown(t);
      words.check('list', on(t, app));
    });
    testWidgets('a running flow picked', (t) async {
      final app = await shown(t, selected: 'heat');
      words.check('running', on(t, app));
    });
    testWidgets('a failing flow picked', (t) async {
      final app = await shown(t, selected: 'alarm');
      words.check('failing', on(t, app));
    });
    testWidgets('a stopped flow picked', (t) async {
      final app = await shown(t, selected: 'old');
      words.check('stopped', on(t, app));
    });
    testWidgets('a flow never deployed picked', (t) async {
      final app = await shown(t, selected: 'draft');
      words.check('draft', on(t, app));
    });
    testWidgets('no flows', (t) async {
      final app = await shown(t, flows: false);
      words.check('empty', on(t, app));
    });
    testWidgets('without config on dataflows', (t) async {
      final app = await shown(t, config: false, selected: 'heat');
      words.check('read only', on(t, app));
    });
    testWidgets('without read on the flow', (t) async {
      final app = ScreenApp(grants: [('$plant/downstream/**', 'write')]);
      await app.logIn(t);
      app.put((s) => withFlows(s, selected: 'heat'));
      await app.pump(t, const FlowsPageConnector());
      words.check('no read', on(t, app));
    });
    testWidgets('in Ukrainian', (t) async {
      final app = await shown(
        t,
        selected: 'alarm',
        locale: const Locale('uk'),
      );
      words.check('uk', on(t, app));
      await S.load(const Locale('en'));
    });
  });

  testWidgets('a row picks its flow; the inspector shows it', (t) async {
    final app = await shown(t);
    expect(app.store.state.flows.selectedFlow, isNull);
    await t.tap(find.text('alarm').first);
    await app.settle(t);
    expect(app.store.state.flows.selectedFlow, 'alarm');
    expect(find.text('rhai: unknown variable `t3`'), findsWidgets);
    await t.tap(find.text('heat').first);
    await app.settle(t);
    expect(app.store.state.flows.selectedFlow, 'heat');
  });

  testWidgets('Flows follows dataflows while it is shown', (t) async {
    final app = await shown(t);
    expect(app.store.state.flows.follow?.lists, ['$plant/dataflows']);
    expect(app.store.state.flows.follow?.values, ['$plant/dataflows/*']);
    await app.leave(t);
    expect(app.store.state.flows.follow, isNull);
  });
}
