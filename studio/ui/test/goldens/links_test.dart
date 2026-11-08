import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../frames/harness.dart';
import '../frames/links.dart';

/// Boards *Studio · Links* and *Links · Quarantine*, one golden each.
void main() {
  if (!Platform.isMacOS) {
    test('goldens', () {}, skip: 'goldens are compared on macOS');
    return;
  }

  Future<void> shoot(WidgetTester tester, String name, Widget page) async {
    tester.view.physicalSize = const Size(1364, 940);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(frame(page));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('$name.png'));
  }

  testWidgets('links local', (t) => shoot(t, 'links_local', linksLocal()));
  testWidgets(
    'links quarantine',
    (t) => shoot(t, 'links_quarantine', linksQuarantine()),
  );
}
