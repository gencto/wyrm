import 'dart:convert';
import 'dart:io';

import 'package:app/connectors/assistant_page_connector.dart';
import 'package:app/mappers/shell_mappers.dart';
import 'package:app/navigation/go_action.dart';
import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/buttons/segmented_tabs.dart';
import 'package:ui/charts/trend.dart';
import 'package:ui/forms/action_form.dart';
import 'package:ui/indicators/arc_spinner.dart';
import 'package:ui/trees/node_tree.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'support/explorer_app.dart';

/// Explorer as the store makes it: every word on the screen (text and
/// tooltips) in its main states, and what each control does to the broker,
/// to the staged changes, the clipboard and the toasts. Written before the
/// connector moved its words into `ui` (studio-rules §5): it holds the
/// words the connector gave then.
///
/// `EXPLORER_DUMP=1 flutter test test/explorer_test.dart` writes the words
/// it sees to `<tmp>/explorer_words.json` instead of comparing them.
void main() {
  setUpAll(() => S.load(const Locale('en')));

  // The words of each state, written once by EXPLORER_DUMP=1 on the
  // connector as it was before studio-rules (2026-11-15) and not
  // regenerated: a change there is a change of what the screen says.
  final expected = {
    for (final MapEntry(:key, :value) in (jsonDecode(
      File('test/support/explorer_words.json').readAsStringSync(),
    ) as Map<String, Object?>).entries)
      key: [for (final w in value! as List<Object?>) '$w'],
  };

  final dump = Platform.environment['EXPLORER_DUMP'] == '1';
  final dumped = <String, List<String>>{};
  tearDownAll(() {
    if (dump) {
      File(
        '${Directory.systemTemp.path}/explorer_words.json',
      ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(dumped));
    }
  });

  /// The words on screen; with [noTrend], not the trend's (its range ends
  /// now when there are no rows).
  List<String> words(WidgetTester t, {bool noTrend = false}) => [
    for (final e in find.byType(RichText).evaluate())
      if (!noTrend || e.findAncestorWidgetOfExactType<Trend>() == null)
        (e.widget as RichText).text.toPlainText(),
    for (final w in t.widgetList<SelectableText>(find.byType(SelectableText)))
      'selectable: ${w.data}',
    for (final w in t.widgetList<Tooltip>(find.byType(Tooltip)))
      'tip: ${w.message ?? w.richMessage?.toPlainText()}',
  ];

  void check(WidgetTester t, String name, {bool noTrend = false}) {
    final got = words(t, noTrend: noTrend);
    if (dump) {
      dumped[name] = got;
      return;
    }
    expect(got, expected[name], reason: name);
  }

  Finder text(String s) => find.byWidgetPredicate(
    (w) =>
        w is RichText &&
        (w.text.toPlainText() == s || w.text.toPlainText().startsWith('$s  ')),
  );

  Future<void> tap(WidgetTester t, ExplorerApp app, String s) async {
    await t.tap(text(s).first);
    await app.settle(t);
  }

  /// A tab of the node on screen (the header has an `Actions` too).
  Future<void> tab(WidgetTester t, ExplorerApp app, String s) async {
    // the tab bar, whatever its id type
    final bar = find.byWidgetPredicate((w) => w is SegmentedTabs);
    await t.tap(find.descendant(of: bar, matching: text(s)).first);
    await app.settle(t);
  }

  Future<void> tapTip(WidgetTester t, ExplorerApp app, String tip) async {
    await t.tap(find.byTooltip(tip).first);
    await app.settle(t);
  }

  /// The checkboxes of the points table: the header's first.
  Finder boxes() =>
      find.byWidgetPredicate((w) => w.runtimeType.toString() == '_Box');

  Future<void> keys(
    WidgetTester t,
    ExplorerApp app,
    LogicalKeyboardKey key, {
    bool meta = false,
    bool shift = false,
  }) async {
    if (meta) {
      await t.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    }
    if (shift) {
      await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    }
    await t.sendKeyEvent(key);
    if (shift) {
      await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    }
    if (meta) {
      await t.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    }
    await app.settle(t);
  }

  List<String> staged(ExplorerApp app) => [
    for (final id in app.store.state.changes.view)
      switch (app.store.state.changes.table[id]) {
        final c? =>
          '${c.op.name} ${c.key} ${c.field}: ${c.from.vm.text} → '
              '${c.to.vm.text}',
        null => id,
      },
  ];

  group('words', () {
    testWidgets('nothing selected', (t) async {
      final app = ExplorerApp();
      await app.pump(t);
      check(t, 'empty');
    });

    testWidgets('a device, its points and the inspector of each', (t) async {
      final app = ExplorerApp();
      await app.pump(t);
      await tap(t, app, 'plc1');
      check(t, 'device');
      await tap(t, app, 'temp');
      check(t, 'point');
      await tap(t, app, 'mode');
      check(t, 'point enum');
      await tap(t, app, 'alarm');
      check(t, 'point failed');
    });

    testWidgets('two points checked: the selection bar', (t) async {
      final app = ExplorerApp();
      await app.pump(t);
      await tap(t, app, 'plc1');
      await t.tap(boxes().at(1));
      await t.tap(boxes().at(2));
      await app.settle(t);
      check(t, 'selection');
    });

    testWidgets('the points filtered', (t) async {
      final app = ExplorerApp();
      await app.pump(t);
      await tap(t, app, 'plc1');
      await t.enterText(find.byType(TextFormField).last, 'mo');
      await app.settle(t);
      check(t, 'points filtered');
    });

    testWidgets('the tree filtered', (t) async {
      final app = ExplorerApp();
      await app.pump(t);
      await t.enterText(find.byType(TextField).first, 'plc');
      await app.settle(t);
      check(t, 'tree filtered');
    });

    testWidgets('a device: parameters, actions, a form, a result', (t) async {
      final app = ExplorerApp();
      await app.pump(t);
      await tap(t, app, 'plc1');
      await tab(t, app, 'Parameters');
      check(t, 'params');
      await tab(t, app, 'Actions');
      check(t, 'actions');
      await tap(t, app, 'Add point');
      check(t, 'action config');
      await tap(t, app, 'Read registers');
      check(t, 'action write');
      await t.enterText(find.byType(TextFormField).last, '10');
      await tap(t, app, 'Run now');
      check(t, 'action result');
    });

    testWidgets('history of a point, and history that failed', (t) async {
      final app = ExplorerApp();
      await app.pump(t);
      await tap(t, app, 'plc1');
      await tab(t, app, 'History');
      check(t, 'history no point');
      await tab(t, app, 'Points');
      await tap(t, app, 'temp');
      await tab(t, app, 'History');
      check(t, 'history');
      app.api.errors['${ExplorerApp.mode} ▸ history'] = WyrmException.of(
        Status.timeout,
        'no answer',
      );
      await tab(t, app, 'Points');
      await tap(t, app, 'mode');
      await tab(t, app, 'History');
      check(t, 'history failed', noTrend: true);
    });

    testWidgets('audit, with the rights and without', (t) async {
      final app = ExplorerApp();
      await app.pump(t);
      await tap(t, app, 'plc1');
      await tab(t, app, 'Audit');
      check(t, 'audit');

      final low = ExplorerApp(level: 'write');
      await low.pump(t);
      await tap(t, low, 'plc1');
      await tab(t, low, 'Audit');
      check(t, 'audit no rights');
    });

    testWidgets('a connection, a link, a flow, a folder', (t) async {
      final app = ExplorerApp();
      await app.pump(t);
      await tap(t, app, 'tcp');
      check(t, 'connection');
      await tap(t, app, 'modbus');
      check(t, 'link');
      await tap(t, app, 'tank');
      check(t, 'flow');
      await tap(t, app, 'storage');
      check(t, 'section');
    });

    testWidgets('offline', (t) async {
      final app = ExplorerApp(connected: false);
      await app.pump(t);
      await tap(t, app, 'plc1');
      await tap(t, app, 'temp');
      check(t, 'offline');
    });

    testWidgets('the value viewer of a point', (t) async {
      final app = ExplorerApp();
      await app.pump(t);
      await tap(t, app, 'plc1');
      await tap(t, app, 'temp');
      await tapTip(t, app, 'View value');
      check(t, 'viewer');
      await tapTip(t, app, 'Close');
      expect(find.byKey(const ValueKey('value-viewer')), findsNothing);
    });

    testWidgets('the node menu and the poll menu', (t) async {
      final app = ExplorerApp();
      await app.pump(t);
      await tap(t, app, 'plc1');
      await tap(t, app, 'Actions');
      check(t, 'node menu');
      await t.tapAt(const Offset(5, 5));
      await app.settle(t);
      await tab(t, app, 'Points');
      await t.tap(boxes().at(1));
      await t.tap(boxes().at(2));
      await app.settle(t);
      await tap(t, app, 'Set poll…');
      check(t, 'poll menu');
    });
  });

  group('controls', () {
    testWidgets('a tree row selects its node and reads its meta', (t) async {
      final app = ExplorerApp();
      await app.pump(t);
      await tap(t, app, 'plc1');
      expect(app.calls('meta').map((c) => c.key), contains(ExplorerApp.dev));
      expect(
        app.calls('subscribe').map((c) => c.key),
        contains('${ExplorerApp.dev}/*'),
      );
      // the triangle closes the connection
      await t.tap(
        find
            .descendant(
              of: find.ancestor(
                of: text('tcp').first,
                matching: find.byType(Row),
              ),
              matching: find.byType(GestureDetector),
            )
            .first,
      );
      await app.settle(t);
      expect(
        find.descendant(of: find.byType(NodeTree), matching: text('plc1')),
        findsNothing,
      );
    });

    testWidgets('Ping, Run now and Stage', (t) async {
      final app = ExplorerApp();
      await app.pump(t);
      await tap(t, app, 'plc1');
      await tap(t, app, 'Ping');
      expect(
        [for (final c in app.calls('invoke')) '${c.key} ▸ ${c.action}'],
        contains('${ExplorerApp.dev} ▸ ping'),
      );
      await tab(t, app, 'Actions');
      await tap(t, app, 'Add point');
      await t.enterText(
        find
            .descendant(
              of: find.byType(ActionForm),
              matching: find.byType(TextFormField),
            )
            .first,
        'flow',
      );
      await tap(t, app, 'Stage');
      expect(staged(app), ['add ${ExplorerApp.dev} Add point: — → name: flow']);
      await tap(t, app, 'Read registers');
      await t.enterText(find.byType(TextFormField).last, '10');
      await tap(t, app, 'Run now');
      expect(
        [
          for (final c in app.calls('invoke'))
            if (c.action == 'read_registers') '${c.args}',
        ],
        [
          '${Value.from({'start': 10})}',
        ],
      );
    });

    testWidgets('a point: edit in place, poll, new value', (t) async {
      final app = ExplorerApp();
      await app.pump(t);
      await tap(t, app, 'plc1');
      await tap(t, app, 'temp');
      await tap(t, app, '500 ms');
      await t.enterText(find.byType(TextFormField).last, '22');
      await tap(t, app, 'Stage');
      expect(staged(app), [
        'edit ${ExplorerApp.temp} poll: 1 s → 500 ms',
        'edit ${ExplorerApp.temp} value: 21.5 → 22',
      ]);
      // the same row again shows the device itself
      await tap(t, app, 'temp');
      expect(find.text('DEVICE'), findsOneWidget);
    });

    testWidgets('the selection: set poll, remove, Esc', (t) async {
      final app = ExplorerApp();
      await app.pump(t);
      await tap(t, app, 'plc1');
      await t.tap(boxes().at(1));
      await t.tap(boxes().at(2));
      await app.settle(t);
      await tap(t, app, 'Set poll…');
      await tap(t, app, '500 ms');
      expect(staged(app), [
        'edit ${ExplorerApp.temp} poll: 1 s → 500 ms',
        'edit ${ExplorerApp.mode} poll: 5 s → 500 ms',
      ]);
      await tap(t, app, 'Remove…');
      expect(staged(app).skip(2), [
        'remove ${ExplorerApp.temp} remove: — → remove',
        'remove ${ExplorerApp.mode} remove: — → remove',
      ]);
      expect(find.text('Clear'), findsNothing);
      // header: every row; Esc clears
      await t.tap(boxes().first);
      await app.settle(t);
      expect(find.text('3 selected'), findsOneWidget);
      await keys(t, app, LogicalKeyboardKey.escape);
      expect(find.text('3 selected'), findsNothing);
    });

    testWidgets('copy: the keys, a key, the value', (t) async {
      final app = ExplorerApp();
      final copied = ExplorerApp.watchClipboard(t);
      await app.pump(t, toasts: true);
      await tap(t, app, 'plc1');

      /// Runs [copy], then finds [said] in a toast before it hides.
      Future<void> says(Future<void> Function() copy, String said) async {
        await copy();
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await t.pump();
        expect(find.text(said), findsOneWidget, reason: said);
        await app.settle(t);
      }

      await says(() => t.tap(find.byTooltip('Copy key').first), 'Key copied');
      await t.tap(boxes().at(1));
      await t.tap(boxes().at(2));
      await app.settle(t);
      await says(() => t.tap(text('Copy keys').first), '2 keys copied');
      await tap(t, app, 'temp');
      Future<void> press(LogicalKeyboardKey key, {bool shift = false}) async {
        await t.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        if (shift) {
          await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        }
        await t.sendKeyEvent(key);
        if (shift) {
          await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        }
        await t.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      }

      await says(() => press(LogicalKeyboardKey.keyC), 'Value copied');
      await says(
        () => press(LogicalKeyboardKey.keyC, shift: true),
        '2 keys copied',
      );
      expect(copied, [
        ExplorerApp.dev,
        '${ExplorerApp.temp}\n${ExplorerApp.mode}',
        '21.5',
        '${ExplorerApp.temp}\n${ExplorerApp.mode}',
      ]);
    });

    testWidgets('⌘-click marks tree rows, Shift-click checks a range', (
      t,
    ) async {
      final app = ExplorerApp();
      final copied = ExplorerApp.watchClipboard(t);
      await app.pump(t);
      await tap(t, app, 'plc1');
      await t.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await t.tap(text('tcp').first);
      await t.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await app.settle(t);
      await keys(t, app, LogicalKeyboardKey.keyC, meta: true, shift: true);
      expect(copied, ['${ExplorerApp.dev}\n${ExplorerApp.conn}']);
      // Shift-click from the first row to the third: three checked
      await t.tap(boxes().at(1));
      await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await t.tap(text('alarm').first);
      await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await app.settle(t);
      expect(find.text('3 selected'), findsOneWidget);
    });

    testWidgets('the node menu picks an action; Copy key', (t) async {
      final app = ExplorerApp();
      final copied = ExplorerApp.watchClipboard(t);
      await app.pump(t);
      await tap(t, app, 'plc1');
      await tap(t, app, 'Actions');
      await tap(t, app, 'Read registers…');
      expect(find.text('Run now'), findsOneWidget);
      await tap(t, app, 'Actions');
      await tap(t, app, 'Copy key');
      expect(copied, [ExplorerApp.dev]);
      // a right click on another row selects it and opens its menu
      final at = t.getCenter(text('tcp').first);
      await t.tapAt(at, buttons: kSecondaryButton);
      await app.settle(t);
      expect(find.text('Add device…'), findsOneWidget);
    });

    testWidgets('a menu waits for its meta; an answer asked over is dropped', (
      t,
    ) async {
      final app = ExplorerApp();
      await app.pump(t);
      app.api.metaDelay = const Duration(seconds: 2);
      // plc1's menu waits for plc1's meta: Actions ▾ spins
      await t.tapAt(t.getCenter(text('plc1').first), buttons: kSecondaryButton);
      await t.pump();
      expect(find.byType(ArcSpinner), findsOneWidget);
      // tcp's menu is asked before plc1's meta answers
      await t.tapAt(t.getCenter(text('tcp').first), buttons: kSecondaryButton);
      await app.settle(t);
      expect(find.byType(ArcSpinner), findsNothing);
      expect(find.text('Add device…'), findsOneWidget);
      expect(find.text('Read registers…'), findsNothing);
    });

    testWidgets('history ranges, audit on a node change', (t) async {
      final app = ExplorerApp();
      await app.pump(t);
      await tap(t, app, 'plc1');
      await tap(t, app, 'temp');
      await tab(t, app, 'History');
      final first = app.calls('history').length;
      expect(first, greaterThan(0));
      await tap(t, app, '24 h');
      final h = app.calls('history');
      expect(h.length, first + 1);
      final from = DateTime.parse(
        '${(h.last.args! as VMap).v['from']}'.replaceAll('"', ''),
      );
      expect(
        ExplorerApp.now.toUtc().difference(from).inMinutes,
        inInclusiveRange(24 * 60 - 1, 24 * 60 + 1),
      );
      await tab(t, app, 'Audit');
      List<Call> tails() => [
        for (final c in app.calls('invoke'))
          if (c.action == 'tail') c,
      ];
      expect(tails(), hasLength(1));
      await tap(t, app, 'tcp');
      expect(tails(), hasLength(2));
    });

    testWidgets('Read again, ⌘J, Edit dataflow', (t) async {
      final app = ExplorerApp();
      await app.pump(t);
      await tap(t, app, 'plc1');
      // the link opc's meta does not answer: `read failed`, Read again
      await tap(t, app, 'opc');
      const opc = '${ExplorerApp.root}/downstream/opc';
      int metas() => [
        for (final c in app.calls('meta'))
          if (c.key == opc) c,
      ].length;
      final before = metas();
      await tap(t, app, 'Read again');
      expect(metas(), before + 1);
      await keys(t, app, LogicalKeyboardKey.keyJ, meta: true);
      expect(find.byType(AssistantDrawerConnector), findsOneWidget);
      await keys(t, app, LogicalKeyboardKey.keyJ, meta: true);
      expect(find.byType(AssistantDrawerConnector), findsNothing);
      await tap(t, app, 'tank');
      await tap(t, app, 'Edit dataflow');
      expect(app.started.whereType<GoAction>(), hasLength(1));
    });
  });
}
