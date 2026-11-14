import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';

import '../frames/harness.dart';
import '../frames/unlock.dart';

/// The boards of the row *Log in, part 2* (unlock-discover.md §1–§3), one
/// golden each, at the canvas's 1440 × 1000 (`UnlockPlatforms` 1440 × 1300)
/// and 2×, every animation paused 4 s in, as the login goldens.
void main() {
  if (!Platform.isMacOS) {
    test('goldens', () {}, skip: 'goldens are compared on macOS');
    return;
  }

  setUpAll(() => S.load(const Locale('en')));

  Future<void> shoot(
    WidgetTester tester,
    String name,
    Widget page, {
    double height = 1000,
  }) async {
    tester.view.physicalSize = Size(2880, height * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    // The boards draw their dialogs' shadows; flutter_test draws a shadow
    // as a solid shape unless told otherwise (and wants it back after).
    debugDisableShadows = false;
    try {
      await tester.pumpWidget(frame(page));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 4000));
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('$name.png'),
      );
    } finally {
      debugDisableShadows = true;
    }
  }

  testWidgets('UnlockOffer', (t) => shoot(t, 'unlock_offer', offer()));
  testWidgets('Unlock', (t) => shoot(t, 'unlock', unlock()));
  testWidgets('UnlockPrompt', (t) => shoot(t, 'unlock_prompt', prompt()));
  testWidgets(
    'UnlockWindows',
    (t) => shoot(t, 'unlock_windows', prompt(platform: 'windows')),
  );
  testWidgets('UnlockFallback', (t) => shoot(t, 'unlock_fallback', fallback()));
  testWidgets('UnlockChanged', (t) => shoot(t, 'unlock_changed', changed()));
  testWidgets(
    'UnlockSignedOut',
    (t) => shoot(t, 'unlock_signed_out', signedOut()),
  );
  testWidgets('UnlockLinux', (t) => shoot(t, 'unlock_linux', linux()));
  testWidgets('UnlockLock', (t) => shoot(t, 'unlock_lock', lock()));
  testWidgets('UnlockStepUp', (t) => shoot(t, 'unlock_step_up', stepUp()));
  testWidgets('UnlockApp', (t) => shoot(t, 'unlock_app', security()));
  testWidgets(
    'UnlockPlatforms',
    (t) => shoot(t, 'unlock_platforms', platforms(), height: 1300),
  );
}
