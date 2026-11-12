import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/charts/trend.dart';
import 'package:ui/charts/trend_scale.dart';

import 'frames/harness.dart';
import 'frames/trend.dart';

const int _m = 60 * 1000000;

TrendSample _s(int min, double? v, {TrendQuality q = .good}) =>
    TrendSample(min * _m, v, q: q);

void main() {
  setUpAll(() => S.load(const Locale('en')));

  group('axis', () {
    test('fits with a step of 1, 2, 2.5 or 5 × 10ⁿ', () {
      final a = TrendAxis.fit(60.4, 86.1);
      expect((a.lo, a.hi, a.step), (60.0, 90.0, 10.0));
      expect(a.ticks, [60, 70, 80, 90]);
      final b = TrendAxis.fit(0.12, 0.81);
      expect(b.step, 0.25);
      expect(b.label(0.5), '0.50');
      expect(TrendAxis.fit(81, 82.4).label(82.5), '82.5');
    });

    test('a flat line still gets an axis around it', () {
      final a = TrendAxis.fit(5, 5);
      expect(a.lo < 5 && a.hi > 5, isTrue);
      expect(a.ticks.length, inInclusiveRange(3, 5));
    });

    test('no values: 0…100', () {
      final a = TrendAxis.fit(double.infinity, -double.infinity);
      expect((a.lo, a.hi), (0.0, 100.0));
    });
  });

  group('trace', () {
    test('a stretch longer than two buckets is a gap; bad rows say so', () {
      final t = trace([
        _s(0, 1),
        _s(5, 2),
        _s(10, null, q: .bad),
        _s(25, 3),
        _s(30, 4),
      ], 5 * _m);
      expect(t.gaps, [const TrendGap(5 * _m, 25 * _m, bad: true)]);
      expect(t.runs.map((r) => r.points.length), [2, 2]);
    });

    test('one missing bucket joins the line', () {
      final t = trace([_s(0, 1), _s(10, 2), _s(15, 3)], 5 * _m);
      expect(t.gaps, isEmpty);
      expect(t.runs.single.points.length, 3);
    });

    test('uncertain rows are a dashed run joined to the solid ones', () {
      final t = trace([
        _s(0, 1),
        _s(5, 2),
        _s(10, 3, q: .uncertain),
        _s(15, 4, q: .uncertain),
        _s(20, 5),
      ], 5 * _m);
      expect([for (final r in t.runs) r.dashed], [false, true, false]);
      expect(t.runs[1].points.first.t, 5 * _m);
      expect(t.runs[2].points.first.t, 15 * _m);
    });

    test('raw rows: the usual spacing decides the gap', () {
      final t = trace([_s(0, 1), _s(1, 1), _s(2, 1), _s(9, 1)], null);
      expect(t.gaps, [const TrendGap(2 * _m, 9 * _m)]);
    });
  });

  test('gaps of several series merge into one band', () {
    expect(
      unionOf([
        const TrendGap(10, 20),
        const TrendGap(15, 30),
        const TrendGap(40, 50),
      ]),
      [
        const TrendGap(10, 30),
        const TrendGap(40, 50),
      ],
    );
  });

  test('the crosshair snaps to the bucket grid, or to a row', () {
    expect(snap(13, step: 5, anchor: 0), 15);
    expect(snap(12, step: 5, anchor: 2), 12);
    expect(snap(13, times: [0, 10, 20]), 10);
    expect(snap(16, times: [0, 10, 20]), 20);
  });

  test('the window stays in the range and keeps its minimum', () {
    expect(clampWindow(-10, 20, 0, 100, 10), (0, 30));
    expect(clampWindow(90, 120, 0, 100, 10), (70, 100));
    expect(clampWindow(50, 52, 0, 100, 10), (46, 56));
    expect(zoomWindow(0, 100, 50, 0.5), (25, 75));
  });

  group('gestures', () {
    Future<void> pump(WidgetTester t, Widget w) async {
      t.view.physicalSize = const Size(1100, 460);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(frame(w));
    }

    Rect plot(WidgetTester t) => t.getRect(
      find.byWidgetPredicate(
        (w) => w is Listener && w.onPointerHover != null,
      ),
    );

    testWidgets('drag on the plot zooms to the span', (t) async {
      final f = trendFrame('idle');
      (int, int)? got;
      await pump(t, trendBoard(f, onWindow: (a, b) => got = (a, b)));
      final r = plot(t);
      final g = await t.startGesture(
        r.centerLeft + Offset(r.width * 0.25, 0),
        kind: .mouse,
      );
      await g.moveTo(r.centerLeft + Offset(r.width * 0.5, 0));
      await g.up();
      final vm = f.vm;
      final span = vm.windowEnd - vm.windowStart;
      expect(got, isNotNull);
      expect(
        (got!.$1 - (vm.windowStart + span ~/ 4)).abs() < span ~/ 100,
        isTrue,
      );
      expect(
        (got!.$2 - (vm.windowStart + span ~/ 2)).abs() < span ~/ 100,
        isTrue,
      );
    });

    testWidgets('a click sets marker A, a double-click resets', (t) async {
      var resets = 0;
      await pump(
        t,
        trendBoard(trendFrame('zoomed'), onReset: () => resets++),
      );
      final at = plot(t).center;
      await t.tapAt(at, kind: .mouse);
      await t.pump();
      expect(find.textContaining(RegExp(r'^A · \d')), findsOneWidget);
      await t.tapAt(at, kind: .mouse);
      await t.pump();
      expect(resets, 1);
    });

    testWidgets('a legend button reports its series', (t) async {
      String? toggled;
      await pump(
        t,
        trendBoard(trendFrame('idle'), onToggle: (id) => toggled = id),
      );
      await t.tap(find.text('Return temp'));
      expect(toggled, 't2');
    });

    testWidgets('Reset zoom shows only while zoomed', (t) async {
      await pump(t, trendBoard(trendFrame('idle')));
      expect(find.text('Reset zoom'), findsNothing);
      await pump(t, trendBoard(trendFrame('zoomed')));
      expect(find.text('Reset zoom'), findsOneWidget);
    });

    testWidgets('a focused handle moves its edge one bucket', (t) async {
      final f = trendFrame('zoomed');
      (int, int)? got;
      await pump(t, trendBoard(f, onWindow: (a, b) => got = (a, b)));
      final brush = t.getRect(
        find.byWidgetPredicate(
          (w) =>
              w is Listener &&
              w.onPointerSignal != null &&
              w.onPointerHover == null,
        ),
      );
      final vm = f.vm;
      final at = (vm.windowEnd - vm.rangeStart) / (vm.rangeEnd - vm.rangeStart);
      await t.tapAt(
        Offset(brush.left + at * brush.width, brush.center.dy),
        kind: .mouse,
      );
      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      expect(got, (f.vm.windowStart, f.vm.windowEnd + f.vm.step!));
    });

    testWidgets('←/→ on the plot move the crosshair, Esc hides it', (t) async {
      await pump(t, trendBoard(trendFrame('hover')));
      expect(find.text('18:45'), findsOneWidget);
      await t.tapAt(plot(t).topLeft + const Offset(4, 4), kind: .mouse);
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('03:55'), findsOneWidget);
      await t.sendKeyEvent(LogicalKeyboardKey.home);
      await t.pump();
      // The brush's first label and the tooltip's time.
      expect(find.text('03:55'), findsNWidgets(2));
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pump();
      expect(find.text('Click A again to clear it'), findsNothing);
      expect(find.text('Click to set marker A'), findsNothing);
    });
  });
}
