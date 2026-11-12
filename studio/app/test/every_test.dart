import 'package:app/common/every.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The clock of a screen that reads again by itself: Access every 10 s
/// while its tab is shown (`access.shown`), System's log every 5 s.
void main() {
  testWidgets('ticks every period while enabled and stops when not', (
    tester,
  ) async {
    var ticks = 0;
    final shown = ValueNotifier(true);
    await tester.pumpWidget(
      ValueListenableBuilder<bool>(
        valueListenable: shown,
        builder: (_, on, _) => Every(
          period: const Duration(seconds: 10),
          enabled: on,
          onTick: () => ticks++,
          child: const SizedBox(),
        ),
      ),
    );

    await tester.pump(const Duration(seconds: 9));
    expect(ticks, 0);
    await tester.pump(const Duration(seconds: 1));
    expect(ticks, 1);
    await tester.pump(const Duration(seconds: 10));
    expect(ticks, 2);

    // The tab is hidden: no more reads.
    shown.value = false;
    await tester.pump();
    await tester.pump(const Duration(seconds: 30));
    expect(ticks, 2);

    // Shown again: the clock starts over.
    shown.value = true;
    await tester.pump();
    await tester.pump(const Duration(seconds: 10));
    expect(ticks, 3);

    // The screen leaves the tree: the timer goes with it.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
    expect(ticks, 3);
  });
}
