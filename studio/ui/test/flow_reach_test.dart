import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/flows/flow_block_view.dart';
import 'package:ui/flows/flow_canvas.dart';
import 'package:ui/flows/flow_legend.dart';
import 'package:ui/flows/flow_menu.dart';
import 'package:ui/flows/shortcut_card.dart';

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
    List<String> picked, {
    List<FlowBlockVm>? blocks,
    String? view,
    double width = 1000,
    void Function(FlowCommand c, {Offset? at})? onCommand,
  }) => frame(
    SizedBox(
      width: width,
      height: 700,
      child: FlowCanvas(
        blocks: blocks ?? tall,
        wires: const [],
        controller: ctl,
        view: view,
        onCommand: onCommand,
        menu: (ids, block, row) => const FlowMenuVm(
          title: 'canvas',
          items: [FlowMenuItemVm(.tidy)],
        ),
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

  /// Three columns of 10 blocks: 1 440 high, it shows whole at about 40 %.
  final big = [
    for (final b in tall)
      if (int.parse(b.id.split('_').last) < 10) b,
  ];

  double scaleOf(TransformationController c) => c.value.entry(0, 0);

  /// Whether every block of [blocks] shows whole above the legend.
  bool allShown(WidgetTester tester, List<FlowBlockVm> blocks) {
    final view = tester.getRect(find.byType(FlowCanvas));
    final legend = tester.getTopLeft(find.byType(FlowLegend)).dy;
    return blocks.every((b) {
      final r = tester.getRect(find.byKey(ValueKey(b.id)));
      return r.left >= view.left &&
          r.right <= view.right &&
          r.top >= view.top &&
          r.bottom <= legend;
    });
  }

  testWidgets('a flow that does not show whole is fitted when it opens, '
      'above the legend', (tester) async {
    screen(tester);
    final ctl = TransformationController();
    addTearDown(ctl.dispose);
    await tester.pumpWidget(canvas(ctl, [], blocks: big, view: 'big'));
    await tester.pump();
    expect(scaleOf(ctl), lessThan(1));
    expect(scaleOf(ctl), greaterThan(FlowCanvas.minScale));
    expect(allShown(tester, big), isTrue);
  });

  testWidgets('another flow opened is fitted again', (tester) async {
    screen(tester);
    final ctl = TransformationController();
    addTearDown(ctl.dispose);
    await tester.pumpWidget(canvas(ctl, [], blocks: big, view: 'a'));
    await tester.pump();
    ctl.value = Matrix4.identity();
    await tester.pumpWidget(canvas(ctl, [], blocks: big, view: 'b'));
    await tester.pump();
    expect(scaleOf(ctl), lessThan(1));
    expect(allShown(tester, big), isTrue);
  });

  testWidgets('a flow that shows whole stays at 100 %', (tester) async {
    screen(tester);
    final ctl = TransformationController();
    addTearDown(ctl.dispose);
    final small = [
      for (final b in big)
        if (b.y < 300 && b.x < 400) b,
    ];
    await tester.pumpWidget(canvas(ctl, [], blocks: small, view: 'small'));
    await tester.pump();
    expect(scaleOf(ctl), 1);
    expect(ctl.value, Matrix4.identity());
  });

  testWidgets('a flow too large for the smallest zoom shows from its '
      'top-left corner', (tester) async {
    screen(tester);
    final ctl = TransformationController();
    addTearDown(ctl.dispose);
    await tester.pumpWidget(canvas(ctl, [], view: 'tall'));
    await tester.pump();
    expect(scaleOf(ctl), FlowCanvas.minScale);
    final first = tester.getRect(find.byKey(ValueKey(tall.first.id)));
    final view = tester.getRect(find.byType(FlowCanvas));
    expect(first.top, greaterThanOrEqualTo(view.top));
    expect(first.left, greaterThanOrEqualTo(view.left));
  });

  testWidgets('the same view is fitted once; Tidy up fits after the blocks '
      'move', (tester) async {
    screen(tester);
    final ctl = TransformationController();
    addTearDown(ctl.dispose);
    final commands = <FlowCommand>[];
    void onCommand(FlowCommand c, {Offset? at}) => commands.add(c);
    await tester.pumpWidget(
      canvas(ctl, [], blocks: big, view: 'big', onCommand: onCommand),
    );
    await tester.pump();
    // The user zooms in: a rebuild of the same flow keeps it.
    ctl.value = Matrix4.identity();
    await tester.pumpWidget(
      canvas(ctl, [], blocks: [...big], view: 'big', onCommand: onCommand),
    );
    await tester.pump();
    expect(ctl.value, Matrix4.identity());

    // Tidy up from the menu of the empty canvas goes out as a command;
    // the next blocks fit.
    await tester.tapAt(
      const Offset(930, 50),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tidy up'));
    await tester.pumpAndSettle();
    expect(commands, [FlowCommand.tidy]);
    final moved = [for (final b in big) b.at(b.x + 2000, b.y)];
    await tester.pumpWidget(
      canvas(ctl, [], blocks: moved, view: 'big', onCommand: onCommand),
    );
    await tester.pump();
    expect(scaleOf(ctl), lessThan(1));
    expect(allShown(tester, moved), isTrue);
  });

  for (final width in [900.0, 480.0]) {
    testWidgets('the legend and the tools are the board size at a canvas '
        '${width.round()} wide', (tester) async {
      tester.view.physicalSize = Size(width, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final ctl = TransformationController();
      addTearDown(ctl.dispose);
      await tester.pumpWidget(canvas(ctl, [], width: width));
      final legend = tester.getSize(find.byType(FlowLegend));
      final zoom = tester.getSize(find.byKey(const ValueKey('flow-zoom')));
      final help = tester.getSize(find.byKey(const ValueKey('flow-help')));
      // ignore: avoid_print, the sizes go to the PR.
      print('canvas $width: legend $legend, zoom $zoom, help $help');
      // Board: text 12, padding 8 x 12, one line where it fits; the
      // zoom and ? are 34 high.
      expect(zoom.height, 34);
      expect(help, const Size(34, 34));
      expect(legend.height, lessThanOrEqualTo(width >= 900 ? 36 : 120));
      final text = tester.widget<Text>(find.text('reads a value'));
      expect(text.style?.fontSize, 12);
    });
  }
}
