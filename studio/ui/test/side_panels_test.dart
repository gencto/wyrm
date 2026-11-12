import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/containers/side_panels.dart';

import 'frames/harness.dart';

const _left = Key('left');
const _center = Key('center');
const _right = Key('right');

/// Holds the widths the way a connector would: what [SidePanels] reports
/// comes back as its input.
class _Host extends StatefulWidget {
  const _Host({required this.calls, this.left, this.right});

  final List<(PanelSide, double)> calls;
  final double? left;
  final double? right;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late double? _l = widget.left;
  late double? _r = widget.right;

  @override
  Widget build(BuildContext context) => SidePanels(
    left: SidePanel(
      width: _l,
      defaultWidth: 260,
      child: const SizedBox.expand(key: _left),
    ),
    center: const SizedBox.expand(key: _center),
    right: SidePanel(
      width: _r,
      defaultWidth: 320,
      child: const SizedBox.expand(key: _right),
    ),
    onChanged: (side, w) {
      widget.calls.add((side, w));
      setState(() => side == .left ? _l = w : _r = w);
    },
  );
}

void main() {
  late List<(PanelSide, double)> calls;

  Future<void> pump(
    WidgetTester tester, {
    double width = 1400,
    double? left,
    double? right,
  }) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    calls = [];
    await tester.pumpWidget(
      frame(_Host(calls: calls, left: left, right: right)),
    );
  }

  double w(WidgetTester tester, Key key) =>
      tester.getSize(find.byKey(key)).width;

  Finder handle(PanelSide side) => find.byKey(ValueKey(side));

  testWidgets('draws the defaults when no width is stored', (tester) async {
    await pump(tester);

    expect(w(tester, _left), 260);
    expect(w(tester, _right), 320);
    expect(w(tester, _center), 1400 - 260 - 320);
  });

  testWidgets('a drag moves the edge within min and max', (tester) async {
    await pump(tester);

    await tester.drag(handle(.left), const Offset(100, 0));
    await tester.pumpAndSettle();
    expect(w(tester, _left), 360);
    expect(calls.last, (PanelSide.left, 360.0));

    await tester.drag(handle(.left), const Offset(600, 0));
    await tester.pumpAndSettle();
    expect(w(tester, _left), SidePanels.leftMax, reason: 'capped at max');

    await tester.drag(handle(.left), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(w(tester, _left), SidePanels.leftMin, reason: 'held at min');

    // The right panel widens when its edge moves left.
    await tester.drag(handle(.right), const Offset(-50, 0));
    await tester.pumpAndSettle();
    expect(w(tester, _right), 370);
    expect(calls.last, (PanelSide.right, 370.0));
  });

  testWidgets('reports once, at the end of a drag', (tester) async {
    await pump(tester);

    final g = await tester.startGesture(tester.getCenter(handle(.left)));
    for (var i = 0; i < 5; i++) {
      await g.moveBy(const Offset(20, 0));
      await tester.pump();
    }
    expect(w(tester, _left), 360, reason: 'follows the pointer');
    expect(calls, isEmpty);

    await g.up();
    await tester.pumpAndSettle(kDoubleTapTimeout);
    expect(calls, [(PanelSide.left, 360.0)]);
  });

  testWidgets('a double click resets the panel to its default', (
    tester,
  ) async {
    await pump(tester, left: 420, right: 500);
    expect(w(tester, _left), 420);

    await tester.tap(handle(.left));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(handle(.left));
    await tester.pumpAndSettle();

    expect(w(tester, _left), 260);
    expect(calls.last, (PanelSide.left, 260.0));
    expect(w(tester, _right), 500, reason: 'the other panel stays');
  });

  testWidgets('a narrow window shrinks both panels and keeps the center', (
    tester,
  ) async {
    // 200 + 280 + 480 = 960 fits in 1000: the panels give up the 380 they
    // are short in proportion to their room above min (200 and 220).
    await pump(tester, width: 1000, left: 400, right: 500);

    expect(w(tester, _center), closeTo(480, 0.01));
    expect(w(tester, _left), closeTo(400 - 380 * 200 / 420, 0.01));
    expect(w(tester, _right), closeTo(500 - 380 * 220 / 420, 0.01));
    expect(calls, isEmpty, reason: 'a shrink is not a choice');

    // A drag cannot take the center below 480 either.
    await tester.drag(handle(.left), const Offset(200, 0));
    await tester.pumpAndSettle();
    expect(w(tester, _center), greaterThanOrEqualTo(480 - 0.01));
  });

  testWidgets('a stored width out of bounds is clamped', (tester) async {
    await pump(tester, left: 5000, right: 10);

    expect(w(tester, _left), SidePanels.leftMax);
    expect(w(tester, _right), SidePanels.rightMin);
  });

  testWidgets('arrow keys move a focused edge by 16 px', (tester) async {
    await pump(tester);
    FocusNode node(PanelSide side) => tester
        .widget<Focus>(
          find.descendant(of: handle(side), matching: find.byType(Focus)),
        )
        .focusNode!;

    node(.left).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(w(tester, _left), 276);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(w(tester, _left), 244);

    node(.right).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(w(tester, _right), 336, reason: '← widens the right panel');
    expect(calls.last, (PanelSide.right, 336.0));
  });

  testWidgets('the edge lights on hover and shows the resize cursor', (
    tester,
  ) async {
    await pump(tester);
    ColoredBox? line() => tester
        .widgetList<ColoredBox>(
          find.descendant(of: handle(.left), matching: find.byType(ColoredBox)),
        )
        .firstOrNull;
    expect(line(), isNull, reason: 'the panel border is the line at rest');

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: tester.getCenter(handle(.left)));
    await tester.pump();

    expect(line(), isNotNull);
    expect(
      tester
          .widget<MouseRegion>(
            find.descendant(
              of: handle(.left),
              matching: find.byType(MouseRegion),
            ),
          )
          .cursor,
      SystemMouseCursors.resizeColumn,
    );
  });

  testWidgets('a mouse drag leaves the edge unlit once the pointer is away', (
    tester,
  ) async {
    await pump(tester);
    final mouse = await tester.startGesture(
      tester.getCenter(handle(.left)),
      kind: PointerDeviceKind.mouse,
    );
    addTearDown(mouse.removePointer);
    await mouse.moveBy(const Offset(40, 0));
    await tester.pump();
    await mouse.up();
    await mouse.moveTo(tester.getCenter(find.byKey(_center)));
    await tester.pumpAndSettle(kDoubleTapTimeout);

    expect(w(tester, _left), 300);
    expect(
      find.descendant(of: handle(.left), matching: find.byType(ColoredBox)),
      findsNothing,
    );
  });
}
