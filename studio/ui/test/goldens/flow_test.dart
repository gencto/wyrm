import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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

  Future<void> shoot(WidgetTester tester, String name, Widget page) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(frame(page));
    // SVG icons decode off the frame.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('$name.png'));
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
    'the Tree tab with a drag in progress',
    (t) => shoot(t, 'flow_tree_drag', flowTreeDrag()),
  );
}
