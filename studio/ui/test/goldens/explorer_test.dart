import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../frames/explorer.dart';
import '../frames/harness.dart';

/// Board *Studio · Explorer* at the canvas's 1440 × 1000, one golden per
/// frame of docs/design/specs/explorer.md §9.
void main() {
  if (!Platform.isMacOS) {
    test('goldens', () {}, skip: 'goldens are compared on macOS');
    return;
  }

  Future<void> shoot(
    WidgetTester tester,
    String name,
    Widget page, {
    Size size = const Size(1440, 1000),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(frame(page));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('$name.png'));
  }

  testWidgets('point', (t) => shoot(t, 'explorer_point', explorerPoint()));
  testWidgets('device', (t) => shoot(t, 'explorer_device', explorerDevice()));
  testWidgets('review', (t) => shoot(t, 'explorer_review', explorerReview()));
  testWidgets('empty', (t) => shoot(t, 'explorer_empty', explorerEmpty()));
  testWidgets(
    'offline',
    (t) => shoot(t, 'explorer_offline', explorerOffline()),
  );
  testWidgets(
    'resized panels',
    (t) => shoot(t, 'explorer_resized', explorerResized()),
  );
  testWidgets('flow', (t) => shoot(t, 'explorer_flow', explorerFlow()));
  testWidgets(
    'folder',
    (t) => shoot(t, 'explorer_folder', explorerFolder()),
  );
  testWidgets(
    'long name',
    (t) => shoot(
      t,
      'explorer_long_name',
      explorerLongName(),
      size: const Size(1100, 800),
    ),
  );
}
