import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/theme/common.dart';

import '../frames/errors.dart';
import '../frames/harness.dart';

/// The canvas row "Errors", one golden per frame at the boards' 1440 × 900
/// (docs/design/specs/errors.md §9), dark and light.
void main() {
  if (!Platform.isMacOS) {
    test('goldens', () {}, skip: 'goldens are compared on macOS');
    return;
  }

  Future<void> shoot(
    WidgetTester tester,
    String name,
    Widget Function() page,
  ) async {
    for (final (suffix, theme) in [
      ('', darkTheme()),
      ('_light', lightTheme()),
    ]) {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(frame(page(), theme: theme));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('$name$suffix.png'),
      );
      // The countdown's timer must not outlive the test.
      await tester.pumpWidget(const SizedBox());
    }
  }

  testWidgets(
    'dialog: rights',
    (t) => shoot(t, 'error_dialog', () => errorDialogFrame('rights')),
  );
  testWidgets(
    'dialog: rights, details open',
    (t) => shoot(
      t,
      'error_dialog_details',
      () => errorDialogFrame('rights', details: true),
    ),
  );
  testWidgets(
    'dialog: reach on a write',
    (t) => shoot(t, 'err_reach', () => errorDialogFrame('reach')),
  );
  testWidgets(
    'dialog: input',
    (t) => shoot(t, 'err_input', () => errorDialogFrame('input')),
  );
  testWidgets(
    'dialog: busy, counting',
    (t) => shoot(t, 'err_busy', () => errorDialogFrame('busy')),
  );
  testWidgets(
    'dialog: gone',
    (t) => shoot(t, 'err_gone', () => errorDialogFrame('gone')),
  );
  testWidgets(
    'dialog: broker, details open',
    (t) => shoot(
      t,
      'err_broker',
      () => errorDialogFrame('broker', details: true),
    ),
  );
  testWidgets(
    'dialog: studio, details open',
    (t) => shoot(
      t,
      'err_studio',
      () => errorDialogFrame('studio', details: true),
    ),
  );
  testWidgets(
    'quiet: toasts and the mark on the row',
    (t) => shoot(t, 'error_quiet', errorQuietFrame),
  );
  testWidgets(
    'quiet: the Problems drawer',
    (t) => shoot(t, 'error_problems', () => errorQuietFrame(drawer: true)),
  );
  testWidgets(
    'a panel that failed to draw',
    (t) => shoot(t, 'error_panel', errorPanelFrame),
  );
  testWidgets(
    'Studio cannot start',
    (t) => shoot(t, 'error_fatal', errorFatalFrame),
  );
}
