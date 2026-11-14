import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../frames/assistant.dart';
import '../frames/harness.dart';

/// Boards *Assistant*, *AssistantRun*, *AssistantDone*, *AssistantFailed*:
/// a task that waits for approval, the same task after a refused approval,
/// its run, and how it ended.
void main() {
  if (!Platform.isMacOS) {
    test('goldens', () {}, skip: 'goldens are compared on macOS');
    return;
  }

  testWidgets('assistant plan', (tester) async {
    tester.view.physicalSize = const Size(1364, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(frame(assistantPlan()));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('assistant_plan.png'),
    );
  });

  testWidgets('assistant approval refused', (tester) async {
    tester.view.physicalSize = const Size(1364, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      frame(
        assistantPlan(
          refusal:
              'step 2 may be sent 290 s after this approval (the waits '
              'before it), and its approval is good for 300 s: leave it out '
              'and ask for it as a follow-up when this plan is done',
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('assistant_refused.png'),
    );
  });

  testWidgets('assistant run', (tester) async {
    tester.view.physicalSize = const Size(1364, 940);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(frame(assistantRun()));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('assistant_run.png'),
    );
  });

  testWidgets('assistant done', (tester) async {
    tester.view.physicalSize = const Size(1364, 940);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(frame(assistantDone()));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('assistant_done.png'),
    );
  });

  testWidgets('assistant failed', (tester) async {
    tester.view.physicalSize = const Size(1364, 940);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(frame(assistantFailed()));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('assistant_failed.png'),
    );
  });
}
