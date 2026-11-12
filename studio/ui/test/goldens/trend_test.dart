import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/theme/common.dart';

import '../frames/harness.dart';
import '../frames/trend.dart';

/// The canvas row "Design system" › Trend chart, one golden per frame at
/// the board's 1100 × 460 (docs/design/specs/trend.md §8), dark and light.
void main() {
  if (!Platform.isMacOS) {
    test('goldens', () {}, skip: 'goldens are compared on macOS');
    return;
  }
  setUpAll(() => S.load(const Locale('en')));

  Future<void> shoot(WidgetTester tester, String name, TrendFrame f) async {
    for (final (suffix, theme) in [
      ('', darkTheme()),
      ('_light', lightTheme()),
    ]) {
      tester.view.physicalSize = const Size(1100, 460);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(frame(trendBoard(f), theme: theme));
      await tester.pump(const Duration(milliseconds: 300));
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('$name$suffix.png'),
      );
      await tester.pumpWidget(const SizedBox());
    }
  }

  testWidgets('Trend', (t) => shoot(t, 'trend', trendFrame('idle')));
  testWidgets(
    'TrendHover',
    (t) => shoot(t, 'trend_hover', trendFrame('hover')),
  );
  testWidgets(
    'TrendZoomed',
    (t) => shoot(t, 'trend_zoomed', trendFrame('zoomed')),
  );
  testWidgets(
    'TrendPinned',
    (t) => shoot(t, 'trend_pinned', trendFrame('pinned')),
  );
  testWidgets('TrendGap', (t) => shoot(t, 'trend_gap', trendFrame('gap')));
  testWidgets(
    'states: loading, refining, nothing recorded, one hidden',
    (t) async {
      await shoot(t, 'trend_loading', trendFrame('idle', loading: true));
      await shoot(t, 'trend_refining', trendFrame('zoomed', refining: true));
      await shoot(t, 'trend_empty', trendFrame('idle', empty: true));
      await shoot(
        t,
        'trend_hidden',
        trendFrame('hover', hidden: {'t2'}),
      );
    },
  );
}
