import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';

import '../frames/harness.dart';
import '../frames/login.dart';

/// Boards *Login*, *LoginSigning*, *LoginWrong*, *LoginUnreachable* and
/// *LoginWelcome* (docs/design/specs/login.md), one golden each, at the
/// canvas's 1440 × 1000 and 2×, like `docs/design/screens/Login*.png`.
///
/// Every animation is paused at the same moment as those PNGs: 4.0 s after
/// the page appeared (the renderer pauses each CSS animation there). The
/// clock is the test's: the first pump starts every ticker, the second moves
/// them all 4 s on. By then the rise, the spine and the shake are over and
/// every loop is at a fixed phase. One more golden shows the idle page as it
/// stands when the system asks for less motion.
void main() {
  if (!Platform.isMacOS) {
    test('goldens', () {}, skip: 'goldens are compared on macOS');
    return;
  }

  // The page's own words come from `S.current`.
  setUpAll(() => S.load(const Locale('en')));

  Future<void> shoot(
    WidgetTester tester,
    String name,
    Widget page, {
    bool reduced = false,
  }) async {
    tester.view.physicalSize = const Size(2880, 2000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    if (reduced) {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
    }
    await tester.pumpWidget(frame(page));
    // SVG icons decode off the frame; the fake clock does not move meanwhile.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 4000));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('$name.png'));
  }

  testWidgets('login idle', (t) => shoot(t, 'login_idle', login()));
  testWidgets(
    'login signing at step 2',
    (t) => shoot(t, 'login_signing', login(stage: 'signing')),
  );
  testWidgets(
    'login wrong password',
    (t) => shoot(t, 'login_wrong', login(stage: 'wrong')),
  );
  testWidgets(
    'login unreachable',
    (t) => shoot(t, 'login_unreachable', login(stage: 'unreachable')),
  );
  testWidgets(
    'login welcome',
    (t) => shoot(t, 'login_welcome', login(stage: 'welcome')),
  );
  testWidgets(
    'login idle, reduced motion',
    (t) => shoot(t, 'login_idle_still', login(), reduced: true),
  );
}
