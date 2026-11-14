import 'package:app/connectors/assistant_page_connector.dart';
import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/assistant/actions/set_chip_action.dart';
import 'package:business/redux/assistant/actions/set_drawer_action.dart';
import 'package:business/redux/live/actions/set_live_values_action.dart';
import 'package:business/redux/nodes/actions/add_nodes_action.dart';
import 'package:business/redux/nodes/actions/select_point_action.dart';
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
    // the drawer watches the found nodes while it is open
    expect(
      app.store.state.assistant.watched,
      containsAll([_link, _plc, _valve]),
    );
    app.store.dispatchSync(SetDrawerAction(open: false));
    await tester.pumpWidget(const SizedBox());
    expect(app.store.state.assistant.watched, isEmpty);
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
      find.byKey(ValueKey('mark-${edit.microsecondsSinceEpoch}')),
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
}
