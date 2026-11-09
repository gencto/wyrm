import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/shell/window_bar.dart';
import 'package:ui/shell/window_controls.dart';

import 'frames/harness.dart';

const _button = Key('button');
const _label = Key('label');

/// A top bar as the pages build one: a label, a gap, a button.
Widget _bar(WindowBarVm vm, {VoidCallback? onButton}) => frame(
  Align(
    alignment: .topCenter,
    child: SizedBox(
      height: 56,
      child: WindowBar(
        vm: vm,
        padding: 16,
        child: Row(
          children: [
            const Text('WYRM', key: _label),
            const Spacer(),
            TextButton(
              key: _button,
              onPressed: onButton ?? () {},
              child: const Text('Review'),
            ),
          ],
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('with a native frame the bar is its padding and nothing else', (
    t,
  ) async {
    await t.pumpWidget(_bar(const WindowBarVm()));

    expect(t.getTopLeft(find.byKey(_label)).dx, 16);
    expect(t.getTopRight(find.byKey(_button)).dx, 800 - 16);
    // No drag layer under the content.
    expect(
      find.descendant(
        of: find.byType(WindowBar),
        matching: find.byType(Stack),
      ),
      findsNothing,
    );
  });

  testWidgets('the room for the window buttons replaces the padding', (
    t,
  ) async {
    await t.pumpWidget(
      _bar(const WindowBarVm(leading: 92, trailing: WindowControls.width)),
    );

    expect(t.getTopLeft(find.byKey(_label)).dx, 92);
    expect(t.getTopRight(find.byKey(_button)).dx, 800 - WindowControls.width);
  });

  testWidgets('a drag anywhere on the bar moves the window', (t) async {
    var drags = 0;
    await t.pumpWidget(_bar(WindowBarVm(onDrag: () => drags++)));

    // On the empty space, on a label and on a control.
    await t.dragFrom(const Offset(400, 28), const Offset(60, 30));
    expect(drags, 1);
    await t.drag(find.byKey(_label), const Offset(60, 30));
    expect(drags, 2);
    await t.drag(find.byKey(_button), const Offset(60, 30));
    expect(drags, 3);
  });

  testWidgets('a control in the bar is clicked at once, not dragged', (
    t,
  ) async {
    var drags = 0;
    var zooms = 0;
    var taps = 0;
    await t.pumpWidget(
      _bar(
        WindowBarVm(onDrag: () => drags++, onZoom: () => zooms++),
        onButton: () => taps++,
      ),
    );

    await t.tap(find.byKey(_button));
    // No wait for a second tap: the double click is not in its arena.
    await t.pump();
    expect(taps, 1);

    await t.tap(find.byKey(_button));
    await t.pump(const Duration(milliseconds: 80));
    await t.tap(find.byKey(_button));
    await t.pump();
    expect(taps, 3);
    expect(zooms, 0);
    expect(drags, 0);
  });

  testWidgets('a double click on the empty space zooms the window', (t) async {
    var zooms = 0;
    await t.pumpWidget(_bar(WindowBarVm(onDrag: () {}, onZoom: () => zooms++)));

    await t.tapAt(const Offset(400, 28));
    await t.pump(const Duration(milliseconds: 80));
    await t.tapAt(const Offset(400, 28));
    await t.pumpAndSettle();
    expect(zooms, 1);
  });

  testWidgets('the window buttons: minimize, maximize or restore, close', (
    t,
  ) async {
    final calls = <String>[];
    Widget controls({required bool maximized}) => frame(
      Align(
        alignment: .topRight,
        child: WindowControls(
          vm: WindowControlsVm(maximized: maximized),
          onMinimize: () => calls.add('minimize'),
          onMaximize: () => calls.add('maximize'),
          onClose: () => calls.add('close'),
        ),
      ),
    );

    await t.pumpWidget(controls(maximized: false));
    expect(t.getSize(find.byType(WindowControls)), const Size(138, 32));
    await t.tap(find.bySemanticsLabel('Minimize'));
    await t.tap(find.bySemanticsLabel('Maximize'));
    await t.tap(find.bySemanticsLabel('Close'));
    expect(calls, ['minimize', 'maximize', 'close']);
    expect(find.bySemanticsLabel('Restore'), findsNothing);

    await t.pumpWidget(controls(maximized: true));
    await t.tap(find.bySemanticsLabel('Restore'));
    expect(calls.last, 'maximize');
    expect(find.bySemanticsLabel('Maximize'), findsNothing);
  });
}
