import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/theme/common.dart';

import '../frames/harness.dart';
import '../frames/history.dart';

/// Board `History` with the trend mounted (docs/design/specs/trend.md §8),
/// dark and light.
void main() {
  if (!Platform.isMacOS) {
    test('goldens', () {}, skip: 'goldens are compared on macOS');
    return;
  }
  setUpAll(() => S.load(const Locale('en')));

  testWidgets('History', (tester) async {
    for (final (suffix, theme) in [
      ('', darkTheme()),
      ('_light', lightTheme()),
    ]) {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(frame(historyFrame(), theme: theme));
      await tester.pump(const Duration(milliseconds: 300));
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('history$suffix.png'),
      );
    }
  });
}
