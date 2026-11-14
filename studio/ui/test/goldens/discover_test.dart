import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';

import '../frames/discover.dart';
import '../frames/harness.dart';

/// Boards *Discover*, *DiscoverScan*, *DiscoverTrust* and *DiscoverNone*
/// (docs/design/specs/unlock-discover.md §4), one golden each, at the
/// canvas's 1440 × 1000 and 2×, every animation paused 4 s in as the log-in
/// goldens are.
void main() {
  if (!Platform.isMacOS) {
    test('goldens', () {}, skip: 'goldens are compared on macOS');
    return;
  }

  setUpAll(() => S.load(const Locale('en')));

  Future<void> shoot(WidgetTester tester, String name, Widget page) async {
    tester.view.physicalSize = const Size(2880, 2000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(frame(page));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 4000));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('$name.png'));
  }

  testWidgets(
    'discover: rows found',
    (t) => shoot(t, 'discover', discover('found')),
  );
  testWidgets(
    'discover: looking',
    (t) => shoot(t, 'discover_scan', discover('scan')),
  );
  testWidgets(
    'discover: check the certificate',
    (t) => shoot(t, 'discover_trust', discover('trust')),
  );
  testWidgets(
    'discover: nothing found',
    (t) => shoot(t, 'discover_none', discover('none')),
  );
}
