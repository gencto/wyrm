import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/containers/refresh_frame.dart';

import '../frames/harness.dart';
import '../frames/links.dart';

/// Boards *Studio · Links* and *Links · Quarantine*, one golden each, and
/// the links refreshing (docs/studio.md §6.7): the table stays, the strip
/// sweeps along the top — paused half way, 700 ms into its 1.4 s — and the
/// subtitle ends in `Updating…`.
void main() {
  if (!Platform.isMacOS) {
    test('goldens', () {}, skip: 'goldens are compared on macOS');
    return;
  }

  Future<void> shoot(
    WidgetTester tester,
    String name,
    Widget page, {
    Duration at = const Duration(milliseconds: 300),
  }) async {
    tester.view.physicalSize = const Size(1364, 940);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(frame(page));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(at);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('$name.png'));
  }

  testWidgets('links local', (t) => shoot(t, 'links_local', linksLocal()));
  testWidgets(
    'links quarantine',
    (t) => shoot(t, 'links_quarantine', linksQuarantine()),
  );
  testWidgets(
    'links refreshing, content kept',
    (t) => shoot(
      t,
      'links_refreshing',
      RefreshFrame(refreshing: true, label: 'Updating…', child: linksLocal()),
      at: const Duration(milliseconds: 700),
    ),
  );
}
