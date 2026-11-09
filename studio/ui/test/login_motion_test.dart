import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:ui/containers/shake.dart';
import 'package:ui/indicators/wyrm_loader.dart';

import 'frames/harness.dart';
import 'frames/login.dart';

/// docs/design/specs/login.md §4: every loop runs while motion is allowed and
/// none does when the system asks for less.
void main() {
  setUpAll(() => S.load(const Locale('en')));

  Future<void> open(WidgetTester tester, Widget page) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(frame(page));
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
  }

  for (final stage in ['idle', 'signing', 'welcome']) {
    testWidgets('$stage: the loops keep running', (tester) async {
      await open(tester, login(stage: stage));

      expect(tester.binding.hasScheduledFrame, isTrue);
    });

    testWidgets('$stage: nothing moves under reduced motion', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );

      await open(tester, login(stage: stage));

      expect(
        tester.binding.hasScheduledFrame,
        isFalse,
        reason: 'no ticker asks for a frame',
      );
    });
  }

  testWidgets('the busy button carries the small loader', (tester) async {
    await open(tester, login(stage: 'signing'));

    final loader = tester.widget<WyrmLoader>(find.byType(WyrmLoader));
    expect(loader.size, WyrmLoaderSize.small);
    expect(find.text('Signing in…'), findsOneWidget);
    expect(find.text('Checking user and password'), findsOneWidget);
  });

  testWidgets('a wrong password shakes the password once', (tester) async {
    await open(tester, login());
    expect(tester.widget<Shake>(find.byType(Shake)).trigger, isNull);

    await tester.pumpWidget(frame(login(stage: 'wrong')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    final moved = tester.getTopLeft(find.text('Password')).dx;
    await tester.pump(const Duration(milliseconds: 400));
    final rest = tester.getTopLeft(find.text('Password')).dx;
    expect(moved, isNot(rest), reason: 'mid-shake it is off its place');
    expect(
      find.textContaining('User or password is wrong.'),
      findsOneWidget,
    );
  });

  testWidgets('the password takes the focus once the refusal is in', (
    tester,
  ) async {
    // The failure arrives while the log-in still runs and the field is
    // disabled; the focus follows when it is over.
    await open(tester, login(stage: 'wrong', busy: true));
    await tester.pumpWidget(frame(login(stage: 'wrong', busy: false)));
    await tester.pump();
    await tester.pump();

    final password = tester.widget<EditableText>(
      find.byType(EditableText).at(2),
    );
    expect(password.focusNode.hasFocus, isTrue);
  });

  for (final width in [1000.0, 600.0]) {
    testWidgets('stacked at $width px wide, nothing overflows', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      for (final stage in ['idle', 'signing', 'unreachable', 'welcome']) {
        await tester.pumpWidget(frame(login(stage: stage)));
        await tester.pump(const Duration(seconds: 1));
        expect(tester.takeException(), isNull, reason: stage);
      }
    });
  }
}
