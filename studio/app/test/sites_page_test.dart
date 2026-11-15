import 'package:app/connectors/sites_page_connector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:models/site_node.dart';
import 'package:models/site_pick.dart';
import 'package:ui/buttons/button.dart';
import 'package:ui/indicators/status_pill.dart';
import 'package:ui/pages/sites_page.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'support/screen_app.dart';
import 'support/sites_fixture.dart';

/// Sites as the store makes it (studio-rules, step 1): every word of the
/// map and of the inspector of each kind of node, in English and
/// Ukrainian, every dialog, and what each control does to the state and
/// the fake broker — not which actions ran, so it holds before and after
/// the rewrite. Where its links lead: `sites_page_links_test.dart`.
void main() {
  final words = ScreenWords('sites');

  Future<ScreenApp> shown(
    WidgetTester t, {
    bool config = true,
    SitePick? selected,
    Locale locale = const Locale('en'),
  }) async {
    final app = ScreenApp(config: config);
    sitesBroker(app.api);
    await app.logIn(t);
    app.put((s) => withSites(s, selected: selected));
    await app.pump(t, const SitesPageConnector(), locale: locale);
    // the upstream's values are collected for 1.2 s, after a value read
    // for up to 2 s
    await app.settle(t, rounds: 50);
    return app;
  }

  List<String> on(WidgetTester t, ScreenApp app) =>
      app.words(t, find.byType(SitesPage));

  List<String> dialog(WidgetTester t, ScreenApp app) =>
      app.words(t, find.byType(Dialog));

  Finder onPage(String text) =>
      find.descendant(of: find.byType(SitesPage), matching: find.text(text));

  final inDialog = find.descendant(
    of: find.byType(Dialog),
    matching: find.byType(Button),
  );

  Future<void> tap(WidgetTester t, ScreenApp app, Finder f) async {
    await t.ensureVisible(f.first);
    await t.tap(f.first);
    await app.settle(t, rounds: 50);
  }

  Future<void> type(WidgetTester t, int field, String text) async {
    await t.enterText(
      find
          .descendant(of: find.byType(Dialog), matching: find.byType(TextField))
          .at(field),
      text,
    );
    await t.pump();
  }

  group('every word', () {
    for (final (name, selected) in [
      ('self', null),
      ('upstream', const SitePick(SiteNode.upstream, 'central')),
      ('downstream', const SitePick(SiteNode.downstream, 'line1')),
      ('waiting broker', const SitePick(SiteNode.waiting, 'line2')),
      ('waiting link', const SitePick(SiteNode.waiting, 'field-x')),
      ('device', const SitePick(SiteNode.device, 'field-gw')),
      ('relayed', const SitePick(SiteNode.relayed, 'line3')),
      ('platform', const SitePick(SiteNode.platform, 'mqtt-cloud')),
    ]) {
      testWidgets('the map, $name picked', (t) async {
        final app = await shown(t, selected: selected);
        words.check(name, on(t, app));
        await app.leave(t);
      });
    }
    testWidgets('without config on sys', (t) async {
      final app = await shown(t, config: false);
      words.check('no config', on(t, app));
      await app.leave(t);
    });
    testWidgets('without config, a waiting broker picked', (t) async {
      final app = await shown(
        t,
        config: false,
        selected: const SitePick(SiteNode.waiting, 'line2'),
      );
      words.check('no config broker', on(t, app));
      await app.leave(t);
    });
    testWidgets('in Ukrainian', (t) async {
      final app = await shown(t, locale: const Locale('uk'));
      words.check('uk', on(t, app));
      await tap(t, app, onPage('line1'));
      words.check('uk downstream', on(t, app));
      await app.leave(t);
      await S.load(const Locale('en'));
    });
  });

  testWidgets('Sites reads its tables and watches sys while shown', (t) async {
    final app = await shown(t);
    final s = app.store.state;
    expect(s.peers.view, [
      'upstream:central',
      'downstream:line1',
      'platform:mqtt-cloud',
      'relayed:line3',
      'device:field-gw',
    ]);
    expect(s.quarantine.view, ['line2', 'field-x']);
    expect(s.links.view, ['modbus', 'field-gw']);
    expect(s.live.watched.keys, containsAll(['$plant/sys/version']));
    await app.leave(t);
    expect(
      app.store.state.live.watched.keys,
      isNot(contains('$plant/sys/version')),
    );
  });

  testWidgets('a node of the map picks it', (t) async {
    final app = await shown(t);
    expect(app.store.state.peers.selectedPeer, isNull);
    await tap(t, app, onPage('central'));
    expect(
      app.store.state.peers.selectedPeer,
      const SitePick(SiteNode.upstream, 'central'),
    );
    await tap(t, app, onPage('link:field-x'));
    expect(
      app.store.state.peers.selectedPeer,
      const SitePick(SiteNode.waiting, 'field-x'),
    );
    await app.leave(t);
  });

  testWidgets('Connect to an upstream: the form of sys/upstream add', (
    t,
  ) async {
    final app = await shown(t);
    // The form of sys/upstream ▸ add, read first, opens at the first tap
    // (before the rules rewrite it opened only at the second: the
    // connector read the detail from the state it was built with).
    await tap(t, app, find.widgetWithText(Button, 'Connect to an upstream'));
    words.check('connect dialog', dialog(t, app));
    await type(t, 0, 'quic://central.example:7447');
    await tap(t, app, inDialog.last);
    final call = app.calls('add').where((c) => c.key.endsWith('upstream'));
    expect(call.single.key, '$plant/sys/upstream');
    expect('${call.single.args}', contains('quic://central.example:7447'));
    expect(find.byType(Dialog), findsNothing);
    await app.leave(t);
  });

  testWidgets('Token for a site below: issued, then shown', (t) async {
    final app = await shown(t);
    await tap(t, app, find.widgetWithText(Button, 'Token for a site below'));
    words.check('token dialog', dialog(t, app));
    await tap(t, app, inDialog.last);
    final call = app.calls('add').where((c) => c.key.endsWith('tokens'));
    expect(call.single.args, Value.from({'count': 1, 'hours': 24}));
    // The token the broker gave, shown once (before the rules rewrite the
    // dialog kept its form: it read the answer from a state built before).
    words.check('token issued', dialog(t, app));
    await app.leave(t);
  });

  testWidgets('the inspector of this broker opens the same dialogs', (
    t,
  ) async {
    final app = await shown(t);
    await tap(t, app, find.text('sys/tokens add'));
    expect(find.byType(Dialog), findsOneWidget);
    expect(dialog(t, app).first, 'Token for a site below');
    await t.tapAt(Offset.zero);
    await app.settle(t);
    await tap(t, app, find.text('sys/upstream add'));
    expect(dialog(t, app).first, 'Connect to an upstream');
    await app.leave(t);
  });

  testWidgets('Deauthorize asks, then deauthorizes the broker below', (
    t,
  ) async {
    final app = await shown(
      t,
      selected: const SitePick(SiteNode.downstream, 'line1'),
    );
    await tap(t, app, find.text('deauthorize'));
    words.check('deauthorize dialog', dialog(t, app));
    final reads = app.calls('children').length;
    await tap(t, app, inDialog.last);
    final call = app.calls('deauthorize').single;
    expect(call.key, '$plant/sys/quarantine');
    expect(call.args, Value.from({'link': 'line1'}));
    // the peers are read again
    expect(app.calls('children').length, greaterThan(reads));
    await app.leave(t);
  });

  testWidgets('Approve lets the waiting broker in', (
    t,
  ) async {
    final app = await shown(
      t,
      selected: const SitePick(SiteNode.waiting, 'line2'),
    );
    await t.enterText(
      find
          .descendant(
            of: find.byType(SitesPage),
            matching: find.byType(TextField),
          )
          .first,
      'SHA256:ab12…',
    );
    await t.pump();
    await t.ensureVisible(find.widgetWithText(Button, 'Approve'));
    await tap(t, app, find.widgetWithText(Button, 'Approve'));
    final approve = app.calls('approve').single;
    expect(approve.key, '$plant/sys/quarantine/line2');
    expect('${approve.args}', contains('SHA256:ab12…'));
    await app.leave(t);
  });

  testWidgets('Reject asks, then rejects the waiting broker', (t) async {
    final app = await shown(
      t,
      selected: const SitePick(SiteNode.waiting, 'line2'),
    );
    await t.ensureVisible(find.widgetWithText(Button, 'Reject'));
    await tap(t, app, find.widgetWithText(Button, 'Reject'));
    words.check('reject dialog', dialog(t, app));
    await tap(t, app, inDialog.last);
    expect(app.calls('reject').single.key, '$plant/sys/quarantine/line2');
    await app.leave(t);
  });

  testWidgets("a device's pill follows its link's state as it comes", (
    t,
  ) async {
    final app = await shown(
      t,
      selected: const SitePick(SiteNode.device, 'field-gw'),
    );
    Finder pill(String word) => find.descendant(
      of: find.byType(StatusPill),
      matching: find.text(word),
    );
    expect(pill('Offline'), findsOneWidget);
    // the link's state, live (as Links' watch writes it)
    app.put(
      (s) => s.copyWith.links(
        table: s.links.table.update(
          'field-gw',
          (l) => l.copyWith(state: 'connected'),
        ),
      ),
    );
    await app.settle(t);
    expect(pill('Connected'), findsOneWidget);
    await app.leave(t);
  });
}
