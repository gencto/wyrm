import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/flows/flow_block_view.dart';
import 'package:ui/flows/flow_canvas.dart';
import 'package:ui/flows/flow_legend.dart';

import 'frames/harness.dart';

/// Every block of a flow larger than the canvas's first size is reached
/// (flow-editor.md §14, owner 2026-11-15: "I can't scroll to the bottom
/// and see all the blocks"): the canvas is as large as its blocks, so the
/// wheel and two fingers pan to the last one at any zoom, the legend does
/// not cover it, and it takes a click there.
void main() {
  setUpAll(() => S.load(const Locale('en')));

  /// Three columns of 30 blocks, 140 apart: 4 300 high, as the old
  /// automatic layout stacked a large flow.
  final tall = [
    for (var c = 0; c < 3; c++)
      for (var i = 0; i < 30; i++)
        FlowBlockVm(
          id: 'b${c}_$i',
          title: 'b${c}_$i',
          x: 40 + 300.0 * c,
          y: 40 + 140.0 * i,
          rows: const [
            FieldRowVm(
              id: 'out:out',
              label: 'Output',
              name: 'out',
              outPort: 'out',
              outMark: PortMark.free,
            ),
          ],
        ),
  ];
  final last = tall.last;

  Widget canvas(
    TransformationController ctl,
    List<String> picked,
  ) => frame(
    SizedBox(
      width: 1000,
      height: 700,
      child: FlowCanvas(
        blocks: tall,
        wires: const [],
        controller: ctl,
        legend: const FlowLegendVm(
          reads: 'reads a value',
          writes: 'writes to a device',
          free: 'free field',
          readOnly: 'no left port = read-only point',
        ),
        actions: FlowBlockActions(
          onSelect: picked.add,
          onBind: (_, _, _) {},
          onRebind: (_, _, _, _) {},
          onUnbind: (_, _) {},
          onDropEntry: (_, _, _) {},
          onResize: (_, {required add}) {},
          refusal: (_, _, _, {replacing}) => null,
        ),
        onClear: () {},
        onMove: (_, {required nudge}) {},
        onDrop: (_, _, _) {},
      ),
    ),
  );

  void screen(WidgetTester tester) {
    tester.view.physicalSize = const Size(1000, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  test('the canvas is as large as its blocks, never below its first size', () {
    expect(FlowCanvas.extentOf(const []), FlowCanvas.size);
    final e = FlowCanvas.extentOf(tall);
    expect(e.height, last.rect.bottom + FlowCanvas.margin);
    expect(e.width, FlowCanvas.size.width);
  });

  /// The last block's header, on the screen, and the top of the legend.
  (Offset, double) where(WidgetTester tester) {
    final r = tester.getRect(find.byKey(ValueKey(last.id)));
    final zoom = r.width / last.width;
    return (
      r.topLeft + Offset(r.width * 0.4, 16 * zoom),
      tester.getTopLeft(find.byType(FlowLegend)).dy,
    );
  }

  for (final zoom in [1.0, 0.25]) {
    testWidgets('the wheel reaches the last block at ${zoom * 100}% and '
        'it takes a click above the legend', (tester) async {
      screen(tester);
      final ctl = TransformationController(
        Matrix4.identity()..scaleByDouble(zoom, zoom, 1, 1),
      );
      addTearDown(ctl.dispose);
      final picked = <String>[];
      await tester.pumpWidget(canvas(ctl, picked));
      final wheel = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(wheel.hover(const Offset(500, 300)));
      for (var i = 0; i < 80; i++) {
        await tester.sendEventToBinding(
          wheel.scroll(const Offset(0, 100)),
        );
      }
      await tester.sendEventToBinding(wheel.scroll(const Offset(100, 0)));
      await tester.pump();
      final (header, legend) = where(tester);
      expect(header.dy, lessThan(legend), reason: 'clear of the legend');
      expect(header.dy, greaterThan(0));
      await tester.tapAt(header);
      await tester.pump();
      expect(picked, [last.id]);
    });
  }

  testWidgets('two fingers reach the last block', (tester) async {
    screen(tester);
    final ctl = TransformationController();
    addTearDown(ctl.dispose);
    final picked = <String>[];
    await tester.pumpWidget(canvas(ctl, picked));
    final pad = await tester.createGesture(kind: PointerDeviceKind.trackpad);
    await pad.panZoomStart(const Offset(500, 300));
    await tester.pump();
    for (var i = 1; i <= 60; i++) {
      await pad.panZoomUpdate(
        const Offset(500, 300),
        pan: Offset(-10.0 * i, -100.0 * i),
      );
      await tester.pump();
    }
    await pad.panZoomEnd();
    await tester.pump();
    final (header, legend) = where(tester);
    expect(header.dy, lessThan(legend));
    expect(header.dy, greaterThan(0));
    await tester.tapAt(header);
    await tester.pump();
    expect(picked, [last.id]);
  });
}
