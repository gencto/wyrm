import 'package:app/connectors/assistant_page_connector.dart';
import 'package:async_redux/async_redux.dart';
import 'package:auto_route/auto_route.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/assistant/actions/set_chip_action.dart';
import 'package:business/redux/assistant/actions/set_drawer_action.dart';
import 'package:business/redux/live/actions/set_live_values_action.dart';
import 'package:business/redux/nodes/actions/add_nodes_action.dart';
import 'package:business/redux/nodes/actions/select_point_action.dart';
import 'package:business/redux/site/actions/view_site_action.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:models/live_value.dart';
import 'package:models/node_info.dart';
import 'package:models/quality.dart' as q;
import 'package:ui/assistant/found_card.dart';
import 'package:ui/charts/trend.dart';
import 'package:ui/overlays/search_palette.dart';
import 'package:ui/theme/common.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'support/assistant_app.dart';

const _plc = 'wy/central/downstream/modbus/tcp/plc1';
const _valve = 'wy/central/downstream/modbus/tcp/plc1/valve';
const _link = 'wy/central/downstream/modbus/tcp';

/// A done task whose model noted three nodes (`found`).
Map<String, Object?> _foundRecord() => {
  ...planRecord(state: 'done'),
  'plan': const <Object?>[],
  'findings': [
    {'key': _link, 'label': 'tcp', 'detail': 'connected · 10.0.4.12:502'},
    {'key': _plc, 'label': 'plc1', 'detail': '4 of 5 points good'},
    {
      'key': _valve,
      'label': 'valve',
      'detail': 'bad since 03:12 · `exception 0x02` [see](http://x)',
    },
  ],
};

Future<void> _drawer(
  WidgetTester tester,
  AssistantApp app, {
  String? point,
}) async {
  await app.pump(tester, selected: 't-1');
  if (point != null) {
    app.store.dispatchSync(SelectPointAction(point));
  }
  app.store.dispatchSync(SetDrawerAction(open: true));
  await tester.pumpWidget(
    StoreProvider<AppState>(
      store: app.store,
      child: MaterialApp(
        theme: darkTheme(),
        localizationsDelegates: const [S.delegate],
        home: const Scaffold(
          body: Row(
            children: [
              Spacer(),
              SizedBox(width: 640, child: AssistantDrawerConnector()),
            ],
          ),
        ),
      ),
    ),
  );
  await app.settle(tester);
}

/// Explorer (with the drawer), the Assistant tab and Flows in a tabs shell
/// that keeps visited tabs mounted, as Studio's does. Returns the shell.
Future<TabsRouter> _tabs(WidgetTester tester, AssistantApp app) async {
  late TabsRouter tabs;
  final router = RootStackRouter.build(
    routes: [
      NamedRouteDef(
        name: 'Shell',
        path: '/',
        initial: true,
        builder: (context, data) => AutoTabsRouter(
          routes: const [
            NamedRoute('Explorer'),
            NamedRoute('Assistant'),
            NamedRoute('Flows'),
          ],
          builder: (context, child) {
            tabs = AutoTabsRouter.of(context);
            return child;
          },
        ),
        children: [
          NamedRouteDef(
            name: 'Explorer',
            path: 'explorer',
            initial: true,
            builder: (context, data) => const Scaffold(
              body: Row(
                children: [
                  Spacer(),
                  SizedBox(width: 640, child: AssistantDrawerConnector()),
                ],
              ),
            ),
          ),
          NamedRouteDef(
            name: 'Assistant',
            path: 'assistant',
            builder: (context, data) =>
                const Scaffold(body: AssistantPageConnector()),
          ),
          NamedRouteDef(
            name: 'Flows',
            path: 'flows',
            builder: (context, data) => const SizedBox(),
          ),
        ],
      ),
    ],
  );
  await tester.pumpWidget(
    StoreProvider<AppState>(
      store: app.store,
      child: MaterialApp.router(
        routerConfig: router.config(),
        theme: darkTheme(),
        localizationsDelegates: const [S.delegate],
      ),
    ),
  );
  await app.settle(tester);
  return tabs;
}

void _live(AssistantApp app, Map<String, q.Quality> qualities) =>
    app.store.dispatchSync(
      SetLiveValuesAction({
        for (final e in qualities.entries)
          e.key: LiveValue(
            time: DateTime.utc(2026),
            value: 1,
            quality: e.value,
          ),
      }),
    );

/// Spec `assistant.md` §5: the drawer's *What I found* rows, its mini
/// timeline, and the key picker of *+ from Explorer*.
void main() {
  setUpAll(() => S.load(const Locale('en')));

  testWidgets("What I found: the model's words as plain text, each mark "
      "from the node's live value", (tester) async {
    final app = AssistantApp()..task('t-1', _foundRecord());
    await _drawer(tester, app);
    _live(app, {_plc: q.Quality.good, _valve: q.Quality.bad});
    await app.settle(tester);

    expect(find.text('WHAT I FOUND · READ ONLY'), findsOneWidget);
    final card = find.byType(FoundCard);
    // the words as the model wrote them: no marks read, no link made
    expect(
      find.descendant(
        of: card,
        matching: find.textContaining(
          'bad since 03:12 · `exception 0x02` [see](http://x)',
          findRichText: true,
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.byType(InkWell)),
      findsNothing,
      reason: 'nothing on the card is a link or a button',
    );
    // marks from the live values: good, bad, and none for a node without one
    expect(find.byTooltip('good now'), findsOneWidget);
    expect(find.byTooltip('bad now'), findsOneWidget);
    expect(find.byTooltip('no value read'), findsOneWidget);
    // a mark follows the live value, never the model's words
    _live(app, {_valve: q.Quality.good});
    await app.settle(tester);
    expect(find.byTooltip('good now'), findsNWidgets(2));
    // the drawer watches the found nodes while it is open, as readers of
    // its own (not the Assistant tab's slot)
    expect(
      app.store.state.live.watched.keys,
      containsAll([_link, _plc, _valve]),
    );
    expect(app.store.state.assistant.watched, isNot(contains(_valve)));
    app.store.dispatchSync(SetDrawerAction(open: false));
    await tester.pumpWidget(const SizedBox());
    expect(app.store.state.live.watched.keys, isNot(contains(_valve)));
  });

  testWidgets('the mini timeline: the selected point, read with the '
      "viewer's rights, with the audit records as marks", (tester) async {
    final now = DateTime.now().toUtc();
    final edit = now.subtract(const Duration(minutes: 20));
    final app = AssistantApp()..task('t-1', _foundRecord());
    app.api
      ..histories[_valve] = [
        for (var i = 0; i < 6; i++)
          HistRow(
            now.subtract(Duration(minutes: 50 - i * 10)).microsecondsSinceEpoch,
            VFloat(11.0 + i),
            i < 3 ? Quality.good : Quality.bad,
          ),
      ]
      ..invokes['wy/central/sys/audit ▸ tail'] = [
        VArray([
          VMap({
            't': VInt(edit.microsecondsSinceEpoch),
            'op': const VStr('invoke'),
            'key': const VStr('$_valve/~act/edit'),
            'sub': const VStr('user:ivan'),
            'status': const VInt(0),
          }),
          // another node: not a mark of this point
          VMap({
            't': VInt(edit.microsecondsSinceEpoch),
            'op': const VStr('set'),
            'key': const VStr('$_plc/other/~set'),
            'sub': const VStr('user:ivan'),
            'status': const VInt(0),
          }),
        ]),
      ];
    await _drawer(tester, app, point: _valve);

    // read through the user's own session (the gateway applies its rights)
    expect(
      [
        for (final c in app.api.calls)
          if (c.op == 'history') c.key,
      ],
      [_valve],
    );
    expect(app.calls('tail'), hasLength(1));
    final trend = tester.widget<Trend>(find.byType(Trend));
    expect(
      (trend.vm.brush, trend.vm.legend, trend.vm.plotHeight),
      (
        false,
        false,
        64.0,
      ),
    );
    expect(trend.vm.marks, [
      TrendMark(
        edit.microsecondsSinceEpoch,
        'user:ivan · invoke modbus/tcp/plc1/valve/~act/edit',
      ),
    ]);
    expect(
      find.byKey(const ValueKey('mark-0')),
      findsOneWidget,
    );
    expect(find.text('From sys/audit'), findsOneWidget);
    expect(
      find.text('user:ivan · invoke modbus/tcp/plc1/valve/~act/edit'),
      findsOneWidget,
    );
    expect(find.text('valve · last 1h'), findsOneWidget);
  });

  testWidgets('without config on sys/audit the timeline reads no tail and '
      'says why', (tester) async {
    final app = AssistantApp(
      roles: const ['operator'],
      grants: const [('wy/central/downstream/**', 'write')],
      max: 'write',
    )..task('t-1', _foundRecord());
    await _drawer(tester, app, point: _valve);

    expect(app.calls('tail'), isEmpty);
    expect(find.text('The audit needs config on sys/audit.'), findsOneWidget);
    expect(find.byType(Trend), findsOneWidget);
  });

  testWidgets('a task without findings and no point shows no card', (
    tester,
  ) async {
    final app = AssistantApp()..task('t-1', planRecord());
    await _drawer(tester, app);
    expect(find.byType(FoundCard), findsNothing);
  });

  testWidgets('+ from Explorer: a key picker over the nodes Explorer read '
      'and a typed key of this site', (tester) async {
    final app = AssistantApp()..task('t-1', planRecord());
    app.api.metas[AssistantApp.agent] = NodeMeta(
      cfg: {
        'allowed_prefixes': Value.from(['wy/central/downstream/modbus']),
      },
    );
    await app.pump(tester, selected: 't-1');
    app.store.dispatchSync(
      AddNodesAction(
        [
          const NodeInfo(key: _link, name: 'tcp'),
          const NodeInfo(key: _plc, name: 'plc1', display: 'Boiler PLC'),
          const NodeInfo(key: _valve, name: 'valve', type: 'number'),
        ].lock,
      ),
    );
    await _drawer(tester, app);

    await tester.tap(find.text('+ from Explorer'));
    await tester.pumpAndSettle();
    final palette = find.byType(SearchPalette);
    expect(palette, findsOneWidget);
    expect(find.text('Boiler PLC'), findsOneWidget);
    expect(find.text('modbus/tcp/plc1/valve'), findsWidgets);
    // filtered by what is typed
    await tester.enterText(find.byType(TextField).last, 'boiler');
    await tester.pump();
    expect(find.text('modbus/tcp/plc1/valve'), findsNothing);
    await tester.tap(find.text('Boiler PLC'));
    await tester.pumpAndSettle();
    expect(app.store.state.assistant.chips, [_plc]);

    // a key typed below the site; one of another site or with `~` is
    // not offered
    await tester.tap(find.text('+ from Explorer'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).last,
      'wy/plant/downstream/x',
    );
    await tester.pump();
    expect(find.textContaining('Attach'), findsNothing);
    await tester.enterText(find.byType(TextField).last, 'downstream/x/~val');
    await tester.pump();
    expect(find.textContaining('Attach'), findsNothing);
    await tester.enterText(
      find.byType(TextField).last,
      'downstream/modbus/rtu',
    );
    await tester.pump();
    await tester.tap(find.text('Attach modbus/rtu'));
    await tester.pumpAndSettle();
    expect(app.store.state.assistant.chips, [
      _plc,
      'wy/central/downstream/modbus/rtu',
    ]);
  });

  testWidgets('+ from Explorer is closed at 16 keys, with the reason', (
    tester,
  ) async {
    final app = AssistantApp()..task('t-1', planRecord());
    await _drawer(tester, app);
    for (var i = 0; i < 17; i++) {
      app.store.dispatchSync(SetChipAction('$_link/p$i'));
    }
    await app.settle(tester);
    expect(app.store.state.assistant.chips, hasLength(16));
    await tester.tap(find.text('+ from Explorer'));
    await tester.pumpAndSettle();
    expect(find.byType(SearchPalette), findsNothing);
    expect(
      find.byTooltip(
        '16 keys are attached, the most one ask takes. Remove one first.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('the finding marks survive a visit to the Assistant tab and '
      'are let go while Explorer is hidden (review M1)', (tester) async {
    final app = AssistantApp()..task('t-1', _foundRecord());
    // the broker answers a subscription with the value it holds
    for (final (k, quality) in [(_plc, Quality.good), (_valve, Quality.bad)]) {
      app.api.initial[k] = [
        ValSample(k, Sample(const VInt(1), q: quality, t: 1)),
      ];
    }
    await app.pump(tester, selected: 't-1');
    app.store.dispatchSync(SetDrawerAction(open: true));
    final tabs = await _tabs(tester, app);
    int readers(String k) => app.store.state.live.watched[k] ?? 0;
    expect(readers(_valve), 1);
    expect(find.byTooltip('bad now'), findsOneWidget);

    // (A) Explorer → Assistant → Explorer: the tab's own watching comes
    // and goes; back on Explorer the drawer's keys are watched and their
    // values read again
    tabs.setActiveIndex(1);
    await app.settle(tester);
    tabs.setActiveIndex(0);
    await app.settle(tester);
    expect(readers(_valve), 1);
    expect(app.store.state.live.values[_valve]?.quality, q.Quality.bad);
    expect(find.byTooltip('bad now'), findsOneWidget);

    // (B) Explorer → Flows: the drawer is hidden with Explorer, its keys
    // are let go; back on Explorer they are watched again
    tabs.setActiveIndex(2);
    await app.settle(tester);
    expect(readers(_valve), 0);
    expect(readers(_plc), 0);
    tabs.setActiveIndex(0);
    await app.settle(tester);
    expect(readers(_valve), 1);
  });

  testWidgets('a finding key that is no plain node key of the site is not '
      'shown nor watched (review L5)', (tester) async {
    final app = AssistantApp()
      ..task('t-1', {
        ..._foundRecord(),
        'findings': [
          {'key': _plc, 'label': 'plc1'},
          {'key': 'wy/central/downstream/**', 'label': 'row-pattern'},
          {'key': 'wy/plant/downstream/x', 'label': 'row-other-site'},
          {'key': '$_valve/~val', 'label': 'row-tilde'},
        ],
      });
    await _drawer(tester, app);
    expect(find.textContaining('plc1', findRichText: true), findsWidgets);
    for (final hidden in ['row-pattern', 'row-other-site', 'row-tilde']) {
      expect(find.textContaining(hidden, findRichText: true), findsNothing);
    }
    final watched = app.store.state.live.watched.keys;
    expect(watched, contains(_plc));
    expect(watched.where((k) => k.contains('*') || k.contains('~')), isEmpty);
    expect(watched, isNot(contains('wy/plant/downstream/x')));
  });

  testWidgets('findings the agent did not note: the card says why', (
    tester,
  ) async {
    final app = AssistantApp()
      ..task('t-1', {
        ..._foundRecord(),
        'findings': const <Object?>[],
        'findings_refused': {'rights_expired': 2, 'limit': 1},
      });
    await _drawer(tester, app);
    expect(find.text('WHAT I FOUND · READ ONLY'), findsOneWidget);
    expect(
      find.textContaining('2 not noted: your rights had expired'),
      findsOneWidget,
    );
    expect(find.text('1 not noted: a task holds at most 12.'), findsOneWidget);
  });

  testWidgets('+ from Explorer offers only keys the agent reads (review L4)', (
    tester,
  ) async {
    final app = AssistantApp()..task('t-1', planRecord());
    app.api.metas[AssistantApp.agent] = NodeMeta(
      cfg: {
        'model': const VStr('claude-opus-5-5'),
        'allowed_prefixes': Value.from(['downstream/modbus/tcp/plc1']),
      },
    );
    await app.pump(tester, selected: 't-1');
    app.store.dispatchSync(
      AddNodesAction(
        [
          const NodeInfo(key: _link, name: 'tcp'),
          const NodeInfo(key: _plc, name: 'plc1'),
          const NodeInfo(key: _valve, name: 'valve'),
          const NodeInfo(key: 'wy/central/pub/models', name: 'models'),
          const NodeInfo(key: '${AssistantApp.agent}/tasks', name: 'tasks'),
        ].lock,
      ),
    );
    await _drawer(tester, app);
    expect(
      app.store.state.assistant.config?.prefixes,
      ['downstream/modbus/tcp/plc1'],
    );

    await tester.tap(find.text('+ from Explorer'));
    await tester.pumpAndSettle();
    final titles = [
      for (final e in tester.widgetList<Text>(
        find.descendant(
          of: find.byType(SearchPalette),
          matching: find.byType(Text),
        ),
      ))
        e.data,
    ];
    expect(titles, containsAll(['plc1', 'valve', 'models']));
    expect(titles, isNot(contains('tcp')), reason: 'above the prefix');
    expect(titles, isNot(contains('tasks')), reason: "the agent's own");
    // a typed key outside is said, not offered
    await tester.enterText(
      find.byType(TextField).last,
      'downstream/modbus/rtu',
    );
    await tester.pump();
    expect(find.textContaining('Attach'), findsNothing);
    await tester.tap(
      find.text('modbus/rtu is outside what the agent may read'),
    );
    await tester.pumpAndSettle();
    expect(app.store.state.assistant.chips, isEmpty);
  });

  testWidgets("another site: the drawer's finding nodes are unwatched, not "
      'moved', (tester) async {
    final app = AssistantApp()..task('t-1', _foundRecord());
    app.api.children_['wy/plant/sys/links'] = [];
    await _drawer(tester, app);
    expect(app.store.state.live.watched[_valve], 1);
    expect(app.store.state.assistant.drawerWatched, contains(_valve));

    app.store.dispatchSync(ViewSiteAction('plant'));
    await app.settle(tester);

    // central's findings went with central: nothing of them is watched
    final watched = app.store.state.live.watched.keys;
    expect(watched, isNot(contains(_valve)));
    expect(watched, isNot(contains(_plc)));
    expect(watched, isNot(contains(_link)));
    expect(
      watched,
      isNot(contains(_valve.replaceFirst('wy/central/', 'wy/plant/'))),
    );
    expect(app.store.state.assistant.drawerWatched, isEmpty);

    // and taking the drawer away later unwatches nothing it does not hold
    await tester.pumpWidget(const SizedBox());
    expect(app.store.state.live.watched.keys, isNot(contains(_valve)));
  });
}
