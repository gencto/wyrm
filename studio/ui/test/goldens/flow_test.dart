import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ui/flows/flow_canvas.dart';

import '../frames/flow.dart';
import '../frames/harness.dart';

/// Boards *Flow editor · fields, bindings, properties* (FlowBind) and *·
/// drag points and actions from the tree* (FlowTree), at the boards' size
/// (1440 × 1000) so a golden sits next to `docs/design/screens/FlowBind.png`.
void main() {
  if (!Platform.isMacOS) {
    test('goldens', () {}, skip: 'goldens are compared on macOS');
    return;
  }

  Future<void> shoot(
    WidgetTester tester,
    String name,
    Widget page, {
    (String, String)? dragging,
  }) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(frame(page));
    // SVG icons decode off the frame.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 300));
    TestGesture? g;
    if (dragging case (final from, final to)) {
      // A wire dragged from one row to another, not let go yet.
      Finder on(String t) =>
          find.descendant(of: find.byType(FlowCanvas), matching: find.text(t));
      final a = tester.getCenter(on(from));
      final b = tester.getCenter(on(to)) + const Offset(30, 4);
      g = await tester.startGesture(a);
      await tester.pump();
      for (var i = 1; i <= 8; i++) {
        await g.moveTo(Offset.lerp(a, b, i / 8)!);
        await tester.pump(const Duration(milliseconds: 16));
      }
    }
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('$name.png'));
    await g?.up();
  }

  testWidgets(
    'block selected',
    (t) => shoot(t, 'flow_block_selected', flowBlockSelected()),
  );
  testWidgets(
    'nothing selected',
    (t) => shoot(t, 'flow_nothing_selected', flowNothingSelected()),
  );
  testWidgets(
    'a bound write wire',
    (t) => shoot(t, 'flow_write_wire', flowWriteWire()),
  );
  testWidgets(
    'a variable block',
    (t) => shoot(t, 'flow_variadic', flowVariadic()),
  );
  testWidgets(
    'a wire dragged onto a field that takes it',
    (t) => shoot(
      t,
      'flow_bind_drag',
      flowNothingSelected(),
      dragging: ('State', 'Else'),
    ),
  );
  testWidgets(
    'a wire dragged onto an output, refused',
    (t) => shoot(
      t,
      'flow_bind_refused',
      flowNothingSelected(),
      dragging: ('State', 'Output'),
    ),
  );
  testWidgets(
    'scale in its linear form',
    (t) => shoot(t, 'flow_scale_linear', flowScale(range: false)),
  );
  testWidgets(
    'scale in its range form',
    (t) => shoot(t, 'flow_scale_range', flowScale(range: true)),
  );
  testWidgets(
    'the Tree tab with a drag in progress',
    (t) => shoot(t, 'flow_tree_drag', flowTreeDrag()),
  );
}
