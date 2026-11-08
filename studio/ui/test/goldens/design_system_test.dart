import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/pages/gallery_page.dart';

import '../frames/harness.dart';

/// Board *Design system*, section by section (docs/studio.md §9: one golden
/// per frame). Compare a changed image with the board before accepting it.
///
/// Goldens are made and compared on macOS: text rasterises differently on
/// Linux, so CI (ubuntu) skips them; `flutter test --update-goldens` on a Mac
/// rewrites them.
void main() {
  if (!Platform.isMacOS) {
    test('goldens', () {}, skip: 'goldens are compared on macOS');
    return;
  }

  Future<void> shoot(
    WidgetTester tester,
    String name,
    Widget section, {
    Size size = const Size(1280, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      frame(
        SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: section,
        ),
      ),
    );
    // SVG icons decode off the frame.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    // Not pumpAndSettle: a spinner never settles.
    await tester.pump(const Duration(milliseconds: 300));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('$name.png'));
  }

  testWidgets(
    'colors',
    (t) => shoot(t, 'design_colors', const ColorSwatches()),
  );
  testWidgets(
    'type',
    (t) =>
        shoot(t, 'design_type', const TypeScale(), size: const Size(1280, 560)),
  );
  testWidgets(
    'status',
    (t) => shoot(
      t,
      'design_status',
      const StatusLanguage(),
      size: const Size(1280, 420),
    ),
  );
  testWidgets(
    'components',
    (t) => shoot(
      t,
      'design_components',
      const ComponentKit(),
      size: const Size(1280, 1500),
    ),
  );
  testWidgets(
    'icons',
    (t) =>
        shoot(t, 'design_icons', const IconGrid(), size: const Size(1280, 640)),
  );
}
