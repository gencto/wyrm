import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/flows/flow_block_view.dart';
import 'package:ui/flows/flow_canvas.dart';

import 'frames/harness.dart';

/// The canvas reads the pointer itself (flow-editor.md §4): a field dragged
/// along a wire onto an input binds it, a refused input says why, a bound
/// input's wire is picked up and moved or dropped, a block stays under the
/// pointer at any zoom and scroll.
void main() {
  late List<(FieldRefVm, String, String)> bound;
  late List<(String, String, String, String)> rebound;
  late List<(String, String)> unbound;
  late List<(String, bool)> resized;
  late List<(String, double, double)> moved;
  late List<(String, double, double)> dropped;

  setUp(() {
    bound = [];
    rebound = [];
    unbound = [];
    resized = [];
    moved = [];
    dropped = [];
  });

  const blocks = [
    FlowBlockVm(
      id: 'a',
      title: 'a',
      x: 40,
      y: 40,
      rows: [
        FieldRowVm(
          id: 'out:out',
          label: 'Output',
          name: 'out',
          value: '1',
          outPort: 'out',
          outMark: PortMark.bound,
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
          label: 'Input max',
          name: 'input_max',
          inPort: 'in.input_max',
          outPort: 'input_max',
          inMark: PortMark.bound,
          outMark: PortMark.free,
        ),
        FieldRowVm(
          id: 'out:remainder',
          label: 'Remainder',
          name: 'remainder',
          outPort: 'remainder',
          outMark: PortMark.free,
        ),
      ],
      variadic: VariadicVm(label: '2 inputs'),
    ),
    FlowBlockVm(
      id: 'c',
      title: 'c',
      x: 400,
      y: 300,
      rows: [
        FieldRowVm(
          id: 'in:in',
          label: 'Input',
          name: 'in',
          inPort: 'in',
          outPort: 'in',
          inMark: PortMark.free,
          outMark: PortMark.free,
        ),
      ],
    ),
  ];
  const wires = [FlowWireVm('a', 'out', 'b', 'in.input_max')];

  Widget canvas({TransformationController? controller, Widget? beside}) =>
      frame(
        Row(
          crossAxisAlignment: .start,
          children: [
            ?beside,
            SizedBox(
              width: 1000,
              height: 700,
              child: FlowCanvas(
                blocks: blocks,
                wires: wires,
                controller: controller,
                actions: FlowBlockActions(
                  onSelect: (_) {},
                  onBind: (f, b, p) => bound.add((f, b, p)),
                  onRebind: (ob, op, b, p) => rebound.add((ob, op, b, p)),
                  onUnbind: (b, r) => unbound.add((b, r)),
                  onDropEntry: (_, _, _) {},
                  onResize: (b, {required add}) => resized.add((b, add)),
                  refusal: (from, block, row, {replacing}) =>
                      row.startsWith('out:') ? 'Outputs cannot be bound' : null,
                ),
                onClear: () {},
                onMove: (id, x, y) => moved.add((id, x, y)),
                onDrop: (e, x, y) => dropped.add((e, x, y)),
              ),
            ),
          ],
        ),
      );

  void screen(WidgetTester tester) {
    tester.view.physicalSize = const Size(1300, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<TestGesture> drag(WidgetTester tester, Offset from, Offset to) async {
    final g = await tester.startGesture(from);
    await tester.pump();
    for (var i = 1; i <= 10; i++) {
      await g.moveTo(Offset.lerp(from, to, i / 10)!);
      await tester.pump(const Duration(milliseconds: 16));
    }
    return g;
  }

  testWidgets('a field dragged along a wire onto an input binds it', (
    tester,
  ) async {
    screen(tester);
    await tester.pumpWidget(canvas());

    final g = await drag(
      tester,
      tester.getCenter(find.text('Output')),
      tester.getCenter(find.text('Input')),
    );
    expect(bound, isEmpty, reason: 'nothing binds before it is let go');
    await g.up();
    await tester.pumpAndSettle();
    expect(bound, hasLength(1));
    expect(bound.single.$1.block, 'a');
    expect(bound.single.$1.port, 'out');
    expect((bound.single.$2, bound.single.$3), ('c', 'in'));
  });

  testWidgets('a refused input says why and takes nothing', (tester) async {
    screen(tester);
    await tester.pumpWidget(canvas());

    final g = await drag(
      tester,
      tester.getCenter(find.text('Output')),
      tester.getCenter(find.text('Remainder')),
    );
    expect(find.text('Outputs cannot be bound'), findsOneWidget);
    await g.up();
    await tester.pumpAndSettle();
    expect(find.text('Outputs cannot be bound'), findsNothing);
    expect(bound, isEmpty);
  });

  testWidgets('a field let go on the empty canvas binds nothing', (
    tester,
  ) async {
    screen(tester);
    await tester.pumpWidget(canvas());
    final g = await drag(
      tester,
      tester.getCenter(find.text('Output')),
      const Offset(700, 600),
    );
    await g.up();
    await tester.pumpAndSettle();
    expect(bound, isEmpty);
    expect(unbound, isEmpty);
    expect(rebound, isEmpty);
  });

  testWidgets('a bound input picks its wire up: moved, or dropped', (
    tester,
  ) async {
    screen(tester);
    await tester.pumpWidget(canvas());
    // The left port of `Input max` (block b at x 400).
    final port = Offset(403, tester.getCenter(find.text('Input max')).dy);

    var g = await drag(tester, port, tester.getCenter(find.text('Input')));
    await g.up();
    await tester.pumpAndSettle();
    expect(rebound, [('b', 'in.input_max', 'c', 'in')]);

    g = await drag(tester, port, const Offset(700, 600));
    await g.up();
    await tester.pumpAndSettle();
    expect(unbound, [('b', 'p:input_max')]);
    expect(bound, isEmpty, reason: 'a picked-up wire is never a new one');
  });

  testWidgets('a double click unbinds; + adds an input', (tester) async {
    screen(tester);
    await tester.pumpWidget(canvas());

    await tester.tap(find.text('Input max'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('Input max'));
    await tester.pumpAndSettle();
    expect(unbound, [('b', 'p:input_max')]);

    await tester.tap(find.text('+'));
    await tester.pump();
    expect(resized, [('b', true)]);
  });

  testWidgets('a block stays under the pointer at zoom 1.5, scrolled', (
    tester,
  ) async {
    screen(tester);
    final ctl = TransformationController(
      Matrix4.translationValues(-30, -20, 0)..scaleByDouble(1.5, 1.5, 1, 1),
    );
    addTearDown(ctl.dispose);
    await tester.pumpWidget(canvas(controller: ctl));
    final before = ctl.value.clone();

    final block = find.byKey(const ValueKey('a'));
    final topLeft = tester.getTopLeft(block);
    // Block a's top-left (40, 40) on the screen: 40 × 1.5 − 30, 40 × 1.5 − 20.
    expect(topLeft, const Offset(30, 40));
    // Grab the header 60 × 12 into the block (1.5 × on the screen).
    final grab = topLeft + const Offset(60 * 1.5, 12 * 1.5);
    final g = await drag(tester, grab, grab + const Offset(180, 90));

    // While it moves, the grab point stays under the pointer.
    expect(
      tester.getTopLeft(block),
      offsetMoreOrLessEquals(topLeft + const Offset(180, 90)),
    );
    expect(ctl.value, before, reason: 'the canvas does not pan with it');
    await g.up();
    await tester.pumpAndSettle();
    // 180 / 1.5 = 120 and 90 / 1.5 = 60 in canvas units: (160, 100).
    expect(moved, [('a', 160.0, 100.0)]);
  });

  testWidgets('a palette entry lands under the pointer at zoom 1.5', (
    tester,
  ) async {
    screen(tester);
    final ctl = TransformationController(
      Matrix4.translationValues(-30, -20, 0)..scaleByDouble(1.5, 1.5, 1, 1),
    );
    addTearDown(ctl.dispose);
    await tester.pumpWidget(
      canvas(
        controller: ctl,
        beside: const SizedBox(
          width: 200,
          height: 700,
          child: Align(
            child: Draggable<String>(
              data: 'type:scale',
              dragAnchorStrategy: pointerDragAnchorStrategy,
              feedback: SizedBox(width: 20, height: 20),
              child: SizedBox(width: 80, height: 30, child: Text('scale')),
            ),
          ),
        ),
      ),
    );
    // The canvas starts at x 200; canvas (500, 300) is on the screen at
    // 200 + 500 × 1.5 − 30, 300 × 1.5 − 20.
    const at = Offset(200 + 750 - 30, 450 - 20);
    final g = await drag(tester, tester.getCenter(find.text('scale')), at);
    await g.up();
    await tester.pumpAndSettle();
    // Top-left = pointer − (24, 16) on the grid: (476, 284) → (480, 280).
    expect(dropped, [('type:scale', 480.0, 280.0)]);
  });

  testWidgets('two fingers on a trackpad and a drag on the empty canvas pan', (
    tester,
  ) async {
    screen(tester);
    final ctl = TransformationController();
    addTearDown(ctl.dispose);
    await tester.pumpWidget(canvas(controller: ctl));

    final pad = await tester.createGesture(kind: PointerDeviceKind.trackpad);
    await pad.panZoomStart(const Offset(700, 500));
    await tester.pump();
    await pad.panZoomUpdate(
      const Offset(700, 500),
      pan: const Offset(-40, -30),
    );
    await tester.pump();
    await pad.panZoomEnd();
    await tester.pump();
    expect(ctl.value.getTranslation().x, -40);
    expect(ctl.value.getTranslation().y, -30);

    final g = await drag(
      tester,
      const Offset(700, 600),
      const Offset(760, 640),
    );
    await g.up();
    await tester.pumpAndSettle();
    expect(ctl.value.getTranslation().x, closeTo(20, 0.01));
    expect(ctl.value.getTranslation().y, closeTo(10, 0.01));
    expect(moved, isEmpty);
  });
}
