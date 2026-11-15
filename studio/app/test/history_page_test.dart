import 'package:app/connectors/history_page_connector.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:models/panel_slot.dart';
import 'package:models/trend_range.dart';
import 'package:ui/buttons/button.dart';
import 'package:ui/charts/trend.dart';
import 'package:ui/containers/side_panels.dart';
import 'package:ui/pages/history_page.dart';

import 'support/history_fixture.dart';
import 'support/screen_app.dart';

/// History as the store makes it (studio-rules, step 1): every word in its
/// main states, in English and Ukrainian (the trend's words follow the
/// clock: its model is read instead), and what each control does to the
/// state and the fake broker — not which actions ran, so it holds before
/// and after the rewrite.
void main() {
  final words = ScreenWords('history');

  Future<ScreenApp> shown(
    WidgetTester t, {
    bool config = true,
    bool groups = true,
    String? selected,
    List<String> points = const [],
    Locale locale = const Locale('en'),
  }) async {
    final app = ScreenApp(config: config);
    historyBroker(app.api);
    await app.logIn(t);
    app.put(
      (s) => withGroups(s, groups: groups, selected: selected, points: points),
    );
    await app.pump(t, const HistoryPageConnector(), locale: locale);
    return app;
  }

  // History's page, whatever its type arguments.
  final page = find.byWidgetPredicate((w) => w is HistoryPage);

  List<String> on(WidgetTester t, ScreenApp app) =>
      app.words(t, page, without: Trend);

  /// The last button of the dialog on top: its confirm or submit.
  final inDialog = find
      .descendant(of: find.byType(Dialog), matching: find.byType(Button))
      .last;

  TrendVm? trend(WidgetTester t) {
    final f = find.byType(Trend);
    return f.evaluate().isEmpty ? null : t.widget<Trend>(f).vm;
  }

  group('every word', () {
    testWidgets('the groups, none picked', (t) async {
      final app = await shown(t);
      words.check('groups', on(t, app));
    });
    testWidgets('a group picked, no point', (t) async {
      final app = await shown(t, selected: 'boiler-1');
      words.check('group', on(t, app));
    });
    testWidgets('one point on the trend', (t) async {
      final app = await shown(t, selected: 'boiler-1', points: [t1]);
      words.check('one point', on(t, app));
      final vm = trend(t)!;
      expect(vm.title, 't1');
      expect([for (final s in vm.series) s.name], ['t1']);
      expect([for (final s in vm.series) s.unit], ['°C']);
      expect([for (final s in vm.series) s.decimals], [1]);
      expect([for (final s in vm.series) s.samples.length], [6]);
      expect(vm.rollup, '5 min avg');
      expect(vm.following, isTrue);
    });
    testWidgets('two points on the trend', (t) async {
      final app = await shown(t, selected: 'boiler-1', points: [t1, t2]);
      words.check('two points', on(t, app));
      final vm = trend(t)!;
      expect(vm.title, 't1, t2');
      expect([for (final s in vm.series) s.decimals], [1, 0]);
    });
    testWidgets('a group recording every 5 s', (t) async {
      final app = await shown(t, selected: 'tank');
      words.check('interval', on(t, app));
    });
    testWidgets('no groups', (t) async {
      final app = await shown(t, groups: false);
      words.check('empty', on(t, app));
    });
    testWidgets('without config on sys/history', (t) async {
      final app = await shown(
        t,
        config: false,
        selected: 'boiler-1',
        points: [t1],
      );
      words.check('read only', on(t, app));
    });
    testWidgets('in Ukrainian', (t) async {
      final app = await shown(
        t,
        selected: 'boiler-1',
        points: [t1],
        locale: const Locale('uk'),
      );
      words.check('uk', on(t, app));
      expect(trend(t)!.rollup, 'середнє за 5 хв');
      await S.load(const Locale('en'));
    });
  });

  testWidgets('History follows sys/history and the points while shown', (
    t,
  ) async {
    final app = await shown(t, selected: 'boiler-1', points: [t1]);
    final follow = app.store.state.historian.follow!;
    expect(follow.lists, [hist, '$hist/boiler-1']);
    expect(follow.values, ['$hist/*', '$hist/*/*', t1]);
    // the picked point's rows were read when History was shown
    expect([for (final c in app.calls('history')) c.key], contains(t1));
    await app.leave(t);
    expect(app.store.state.historian.follow, isNull);
  });

  testWidgets('a group, a point, ctrl-click and a range', (t) async {
    final app = await shown(t);
    await t.tap(find.text('tank'));
    await app.settle(t);
    expect(app.store.state.historian.selected, 'tank');
    expect(app.store.state.historian.follow!.lists, [hist, '$hist/tank']);

    await t.tap(find.text('boiler-1'));
    await app.settle(t);
    expect(app.store.state.historian.selected, 'boiler-1');
    expect(app.store.state.historian.points, isEmpty);

    // a plain click: the trend shows that point alone, read at once
    await t.tap(find.text('downstream/plc1/t2'));
    await app.settle(t);
    expect(app.store.state.historian.points, [t2]);
    expect(app.store.state.historian.series.keys, [t2]);
    expect(trend(t)!.title, 't2');

    // a ctrl-click adds a point
    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await t.tap(find.text('downstream/plc1/t1'));
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await app.settle(t);
    expect(app.store.state.historian.points, [t2, t1]);
    expect(trend(t)!.title, 't2, t1');

    // a range reads the series again
    final reads = app.calls('history').length;
    await t.tap(find.text('7 d'));
    await app.settle(t);
    expect(app.store.state.historian.range, TrendRange.week);
    expect(app.calls('history').length, greaterThan(reads));
    await app.leave(t);
  });

  testWidgets('the panels keep the width the user drags them to', (t) async {
    final app = await shown(t, selected: 'boiler-1');
    await t.drag(
      find.byKey(const ValueKey(PanelSide.left)),
      const Offset(60, 0),
    );
    await app.settle(t);
    expect(
      app.store.state.panels.widths[PanelSlot.historyGroups],
      greaterThan(240),
    );
    await app.leave(t);
  });

  testWidgets('Remove group asks, then removes it on the broker', (t) async {
    final app = await shown(t, selected: 'boiler-1', points: [t1]);
    final reads = app.calls('history').length;
    await t.ensureVisible(find.text('Remove the group'));
    await t.tap(find.text('Remove the group'));
    await app.settle(t);
    expect(
      find.text('It stops recording; its rows stay unless you purge them.'),
      findsNWidgets(2),
    );
    await t.tap(inDialog);
    await app.settle(t);
    expect([for (final c in app.calls('remove')) c.key], ['$hist/boiler-1']);
    // the trend is read again
    expect(app.calls('history').length, greaterThan(reads));
    await app.leave(t);
  });

  testWidgets('Stop recording unsubscribes the picked point', (t) async {
    final app = await shown(t, selected: 'boiler-1', points: [t1]);
    await t.ensureVisible(find.text('Stop recording'));
    await t.tap(find.text('Stop recording'));
    await app.settle(t);
    await t.tap(inDialog);
    await app.settle(t);
    expect(
      [
        for (final c in app.calls('unsubscribe')) c.key,
      ],
      ['$hist/boiler-1/w1'],
    );
    await app.leave(t);
  });

  testWidgets('the add button opens the form of add_watch_group', (t) async {
    final app = await shown(t);
    await t.tap(find.byIcon(Icons.add));
    await app.settle(t);
    expect(find.text('Add watch group'), findsWidgets);
    await t.enterText(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(TextField),
      ),
      'pumps',
    );
    await t.pump();
    await t.tap(inDialog);
    await app.settle(t);
    final call = app.calls('add_watch_group').single;
    expect(call.key, hist);
    expect('${call.args}', contains('pumps'));
    await app.leave(t);
  });
}
