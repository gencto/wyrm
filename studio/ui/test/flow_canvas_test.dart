import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/flows/flow_block_view.dart';
import 'package:ui/flows/flow_canvas.dart';

import 'frames/harness.dart';

/// Binding on the canvas: a row with an output is dragged onto a row with an
/// input inside the zoomable canvas; a double click unbinds; − / + resize.
void main() {
  final bound = <(FieldRefVm, String, String)>[];
  final unbound = <(String, String)>[];
  final resized = <(String, bool)>[];

  Widget canvas() => frame(
    SizedBox(
      width: 1000,
      height: 700,
      child: FlowCanvas(
        blocks: const [
          FlowBlockVm(
            id: 'a',
            title: 'a',
            x: 40,
            y: 40,
            rows: [
              FieldRowVm(
                id: 'out:out',
                label: 'out',
                value: '1',
                outPort: 'out',
                outMark: PortMark.free,
              ),
            ],
          ),
          FlowBlockVm(
            id: 'b',
            title: 'b',
            x: 400,
            y: 40,
            rows: [
              FieldRowVm(
                id: 'p:input_max',
                label: 'input_max',
                inPort: 'in.input_max',
                outPort: 'input_max',
                inMark: PortMark.bound,
                outMark: PortMark.free,
              ),
            ],
            variadic: VariadicVm(label: '2 inputs'),
          ),
        ],
        wires: const [],
        actions: FlowBlockActions(
          onSelect: (_) {},
          onMove: (_, _) {},
          onMoveEnd: (_) {},
          onBind: (f, b, p) => bound.add((f, b, p)),
          onUnbind: (b, r) => unbound.add((b, r)),
          onDropEntry: (_, _, _) {},
          onResize: (b, {required add}) => resized.add((b, add)),
        ),
        onClear: () {},
        onMove: (_, _, _) {},
        onDrop: (_, _, _) {},
      ),
    ),
  );

  testWidgets('a field dragged onto an input binds it', (tester) async {
    tester.view.physicalSize = const Size(1000, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(canvas());

    final from = tester.getCenter(find.text('out:'));
    final to = tester.getCenter(find.text('input_max:'));
    final g = await tester.startGesture(from);
    for (var i = 1; i <= 10; i++) {
      await g.moveTo(Offset.lerp(from, to, i / 10)!);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await tester.pumpAndSettle();
    expect(bound, hasLength(1));
    expect(bound.single.$1, const FieldRefVm('a', 'out', label: 'a.out'));
    expect((bound.single.$2, bound.single.$3), ('b', 'in.input_max'));

    await tester.tap(find.text('input_max:'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('input_max:'));
    await tester.pumpAndSettle();
    expect(unbound, [('b', 'p:input_max')]);

    await tester.tap(find.text('+'));
    await tester.pump();
    expect(resized, [('b', true)]);
  });
}
