import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';

import '../frames/explorer.dart';
import '../frames/harness.dart';

/// Board *Studio · Explorer* at the canvas's 1440 × 1000, one golden per
/// frame of docs/design/specs/explorer.md §9.
void main() {
  if (!Platform.isMacOS) {
    test('goldens', () {}, skip: 'goldens are compared on macOS');
    return;
  }

  // The account menu's words.
  setUpAll(() => S.load(const Locale('en')));

  Future<void> shoot(
    WidgetTester tester,
    String name,
    Widget page, {
    Size size = const Size(1440, 1000),
    String? tap,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(frame(page));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 300));
    if (tap != null) {
      await tester.tap(find.text(tap));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 300));
    }
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('$name.png'));
  }

  testWidgets('point', (t) => shoot(t, 'explorer_point', explorerPoint()));
  testWidgets(
    'the point value in the viewer',
    (t) => shoot(t, 'explorer_viewer', explorerViewer()),
  );
  testWidgets(
    'the account menu: user, language, theme, log out',
    (t) => shoot(t, 'explorer_account_menu', explorerPoint(), tap: 'OL'),
  );
  testWidgets(
    'no title bar on macOS: room for the native buttons',
    (t) => shoot(t, 'explorer_window_macos', explorerWindowMacos()),
  );
  testWidgets(
    'no title bar on Windows and Linux: the window buttons',
    (t) => shoot(t, 'explorer_window_controls', explorerWindowControls()),
  );
  testWidgets(
    'the window buttons of a maximized window, at the smallest window',
    (t) => shoot(
      t,
      'explorer_window_maximized',
      explorerWindowControls(maximized: true),
      size: const Size(1180, 680),
    ),
  );
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
