import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:ui/flows/flow_block_view.dart';
import 'package:ui/flows/flow_canvas.dart';
import 'package:ui/flows/flow_menu.dart';
import 'package:ui/flows/shortcut_card.dart';

import 'frames/harness.dart';

/// The canvas reads the pointer itself (flow-editor.md §4): a field dragged
/// along a wire onto an input binds it, a refused input says why, a bound
/// input's wire is picked up and moved or dropped, a block stays under the
/// pointer at any zoom and scroll. And its tools (§12–§14): the marquee
/// and the selection, the keys of the shortcut table, zoom, the context
/// menu.
void main() {
  // The card and the menu read their words from `S.current`.
  setUpAll(() => S.load(const Locale('en')));

  late Set<String> selected;
  late List<(FlowCommand, Offset?)> commands;
  late List<(String, String, bool)> pins;
  late List<(String, String)> viewed;
  late List<bool> nudges;
  var cleared = 0;

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
    selected = {};
    commands = [];
    pins = [];
    viewed = [];
    nudges = [];
    cleared = 0;
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

  // The selection lives outside the canvas, as in the app: the harness
  // keeps it and hands the blocks back marked.
  Widget canvas({
    TransformationController? controller,
    Widget? beside,
  }) => frame(
    Row(
      crossAxisAlignment: .start,
      children: [
        ?beside,
        SizedBox(
          width: 1000,
          height: 700,
          child: StatefulBuilder(
            builder: (context, setState) => FlowCanvas(
              blocks: [
                for (final b in blocks)
                  b.marked(selected: selected.contains(b.id)),
              ],
              wires: wires,
              controller: controller,
              onSelectMany: (ids, {required add, required toggle}) =>
                  setState(() {
                    if (toggle) {
                      for (final id in ids) {
                        if (!selected.remove(id)) {
                          selected.add(id);
                        }
                      }
                    } else {
                      selected = {if (add) ...selected, ...ids};
                    }
                  }),
              onCommand: (c, {at}) => commands.add((c, at)),
              onPin: (b, f, {required pinned}) => pins.add((b, f, pinned)),
              onViewField: (b, r) => viewed.add((b, r)),
              menu: (ids, block, row) => FlowMenuVm(
                title: block ?? 'canvas',
                subtitle: '${ids.length}',
                items: const [
                  FlowMenuItemVm(.copy),
                  FlowMenuItemVm(.paste),
                  FlowMenuItemVm(.fields),
                  FlowMenuItemVm(.unpin),
                  FlowMenuItemVm(
                    .createCustomBlock,
                    disabledReason: 'needs the engine',
                  ),
                ],
                fields: block == null
                    ? const []
                    : const [
                        FlowPinVm(id: 'p:a', label: 'Alpha', pinned: true),
                        FlowPinVm(id: 'p:b', label: 'Beta', pinned: false),
                        FlowPinVm(
                          id: 'p:c',
                          label: 'Gamma',
                          pinned: true,
                          lockedReason: 'bound',
                        ),
                      ],
                unpin: row == null
                    ? null
                    : FlowPinVm(id: row, label: 'Row', pinned: true),
              ),
              actions: FlowBlockActions(
                onSelect: (id) => setState(() => selected = {id}),
                onBind: (f, b, p) => bound.add((f, b, p)),
                onRebind: (ob, op, b, p) => rebound.add((ob, op, b, p)),
                onUnbind: (b, r) => unbound.add((b, r)),
                onDropEntry: (_, _, _) {},
                onResize: (b, {required add}) => resized.add((b, add)),
                refusal: (from, block, row, {replacing}) =>
                    row.startsWith('out:') ? 'Outputs cannot be bound' : null,
              ),
              onClear: () => setState(() {
                selected = {};
                cleared++;
              }),
              onMove: (to, {required nudge}) {
                nudges.add(nudge);
                moved.addAll([
                  for (final e in to.entries) (e.key, e.value.dx, e.value.dy),
                ]);
              },
              onDrop: (e, x, y) => dropped.add((e, x, y)),
            ),
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

  Future<void> withKey(
    WidgetTester tester,
    LogicalKeyboardKey modifier,
    Future<void> Function() body,
  ) async {
    await tester.sendKeyDownEvent(modifier);
    await body();
    await tester.sendKeyUpEvent(modifier);
    await tester.pump();
  }

  // Tests run as Android: the primary modifier is Ctrl.
  Future<void> primary(WidgetTester tester, LogicalKeyboardKey key) => withKey(
    tester,
    LogicalKeyboardKey.controlLeft,
    () => tester.sendKeyEvent(key),
  );

  double scaleOf(TransformationController c) => c.value.entry(0, 0);

  testWidgets('two fingers, Space + drag, the middle button and the wheel '
      'pan; a drag on the empty canvas does not', (tester) async {
    screen(tester);
    final ctl = TransformationController();
    addTearDown(ctl.dispose);
    await tester.pumpWidget(canvas(controller: ctl));
    (double, double) at() =>
        (ctl.value.getTranslation().x, ctl.value.getTranslation().y);

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
    expect(at(), (-40, -30));

    await withKey(tester, LogicalKeyboardKey.space, () async {
      final g = await drag(
        tester,
        const Offset(700, 600),
        const Offset(760, 640),
      );
      await g.up();
    });
    expect(at().$1, closeTo(20, 0.01));
    expect(at().$2, closeTo(10, 0.01));

    final middle = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kMiddleMouseButton,
    );
    await middle.down(const Offset(700, 600));
    await middle.moveBy(const Offset(-20, -10));
    await middle.up();
    await tester.pump();
    expect(at().$1, closeTo(0, 0.01));
    expect(at().$2, closeTo(0, 0.01));

    final wheel = TestPointer(7, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(wheel.hover(const Offset(700, 600)));
    await tester.sendEventToBinding(wheel.scroll(const Offset(0, 50)));
    await tester.pump();
    expect(at(), (0, -50));
    await tester.sendEventToBinding(wheel.removePointer());

    final before = ctl.value.clone();
    final g = await drag(
      tester,
      const Offset(700, 600),
      const Offset(760, 640),
    );
    await g.up();
    await tester.pumpAndSettle();
    expect(ctl.value, before, reason: 'a marquee, not a pan');
    expect(moved, isEmpty);
  });

  testWidgets('a marquee selects what it touches, at zoom 1.5 and scrolled; '
      'Shift adds; a click on the empty canvas clears', (tester) async {
    screen(tester);
    final ctl = TransformationController(
      Matrix4.translationValues(-30, -20, 0)..scaleByDouble(1.5, 1.5, 1, 1),
    );
    addTearDown(ctl.dispose);
    await tester.pumpWidget(canvas(controller: ctl));
    final before = ctl.value.clone();
    // On the screen: a at (30, 40), b at (570, 40) … (900, 250), c at
    // (570, 430) … (900, 541).
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('b'))),
      const Offset(570, 40),
    );

    var g = await drag(tester, const Offset(520, 20), const Offset(950, 300));
    // The rectangle is drawn from where the press went down to the
    // pointer, whatever the zoom and the scroll.
    final box = tester.getRect(find.byKey(const ValueKey('flow-marquee')));
    expect(box.topLeft, offsetMoreOrLessEquals(const Offset(520, 20)));
    expect(box.bottomRight, offsetMoreOrLessEquals(const Offset(950, 300)));
    expect(selected, isEmpty, reason: 'nothing is selected before it ends');
    await g.up();
    await tester.pumpAndSettle();
    expect(selected, {'b'});
    expect(find.byKey(const ValueKey('flow-marquee')), findsNothing);
    expect(ctl.value, before, reason: 'the canvas does not pan with it');

    await withKey(tester, LogicalKeyboardKey.shiftLeft, () async {
      g = await drag(tester, const Offset(960, 600), const Offset(700, 500));
      await g.up();
    });
    await tester.pumpAndSettle();
    expect(selected, {'b', 'c'}, reason: 'Shift adds to the selection');

    // A marquee over nothing, then a click: both clear.
    g = await drag(tester, const Offset(20, 300), const Offset(200, 600));
    await g.up();
    await tester.pumpAndSettle();
    expect(selected, isEmpty);
    await tester.tapAt(const Offset(950, 650));
    await tester.pump();
    expect(cleared, 2);
  });

  testWidgets('Shift-click adds a block; a header moves the whole '
      'selection; a click on one of them selects it alone', (tester) async {
    screen(tester);
    await tester.pumpWidget(canvas());
    const headA = Offset(150, 56);
    const headB = Offset(510, 56);

    await tester.tapAt(headA);
    await tester.pump();
    expect(selected, {'a'});
    await withKey(
      tester,
      LogicalKeyboardKey.shiftLeft,
      () => tester.tapAt(headB),
    );
    expect(selected, {'a', 'b'});

    final g = await drag(tester, headA, headA + const Offset(62, 38));
    // Both follow the pointer while it moves.
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('b'))),
      offsetMoreOrLessEquals(const Offset(462, 78)),
    );
    await g.up();
    await tester.pumpAndSettle();
    // The grabbed block lands on the grid, the other keeps its place
    // beside it.
    expect(moved, [('a', 100.0, 80.0), ('b', 460.0, 80.0)]);
    expect(nudges, [false]);
    expect(selected, {'a', 'b'});

    await tester.tapAt(headB);
    await tester.pump();
    expect(selected, {'b'});

    await withKey(
      tester,
      LogicalKeyboardKey.controlLeft,
      () => tester.tapAt(headB),
    );
    expect(selected, isEmpty, reason: 'Ctrl-click takes it out');
  });

  testWidgets('the keys of the shortcut table', (tester) async {
    screen(tester);
    final ctl = TransformationController();
    addTearDown(ctl.dispose);
    await tester.pumpWidget(canvas(controller: ctl));

    await primary(tester, LogicalKeyboardKey.keyA);
    expect(selected, {'a', 'b', 'c'});

    // The arrows: one grid step; with Shift, ten.
    await tester.tapAt(const Offset(150, 56));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(moved, [('a', 60.0, 40.0)]);
    await withKey(
      tester,
      LogicalKeyboardKey.shiftLeft,
      () => tester.sendKeyEvent(LogicalKeyboardKey.arrowDown),
    );
    expect(moved.last, ('a', 40.0, 240.0));
    await withKey(
      tester,
      LogicalKeyboardKey.shiftLeft,
      () => tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft),
    );
    expect(moved.last, ('a', 0.0, 40.0), reason: 'it stays on the canvas');
    expect(nudges, everyElement(isTrue));

    for (final key in [
      LogicalKeyboardKey.keyC,
      LogicalKeyboardKey.keyX,
      LogicalKeyboardKey.keyV,
      LogicalKeyboardKey.keyD,
      LogicalKeyboardKey.keyZ,
      LogicalKeyboardKey.keyY,
    ]) {
      await primary(tester, key);
    }
    await withKey(
      tester,
      LogicalKeyboardKey.shiftLeft,
      () => primary(tester, LogicalKeyboardKey.keyZ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    expect(
      [for (final c in commands) c.$1],
      [
        FlowCommand.copy,
        FlowCommand.cut,
        FlowCommand.paste,
        FlowCommand.duplicate,
        FlowCommand.undo,
        FlowCommand.redo,
        FlowCommand.redo,
        FlowCommand.delete,
        FlowCommand.delete,
      ],
    );
    // A paste by the keyboard lands where the pointer was last on the
    // canvas (the press on block a's header).
    expect(commands[2].$2, const Offset(150, 56));

    // Zoom: ⌘/Ctrl +, −, 0; 1 is 100 %; Shift+1 fits every block.
    await primary(tester, LogicalKeyboardKey.equal);
    expect(scaleOf(ctl), closeTo(1.2, 1e-9));
    await primary(tester, LogicalKeyboardKey.minus);
    await primary(tester, LogicalKeyboardKey.minus);
    expect(scaleOf(ctl), closeTo(1 / 1.2, 1e-9));
    await primary(tester, LogicalKeyboardKey.digit0);
    expect(scaleOf(ctl), closeTo(1, 1e-9));
    ctl.value = Matrix4.translationValues(-900, -700, 0)
      ..scaleByDouble(2, 2, 1, 1);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    expect(scaleOf(ctl), closeTo(1, 1e-9));
    ctl.value = Matrix4.translationValues(-900, -700, 0)
      ..scaleByDouble(2, 2, 1, 1);
    await tester.pump();
    await withKey(
      tester,
      LogicalKeyboardKey.shiftLeft,
      () => tester.sendKeyEvent(LogicalKeyboardKey.digit1),
    );
    await tester.pump();
    expect(scaleOf(ctl), lessThanOrEqualTo(1));
    const view = Rect.fromLTWH(0, 0, 1000, 700);
    for (final id in ['a', 'b', 'c']) {
      final r = tester.getRect(find.byKey(ValueKey(id)));
      expect(view.contains(r.topLeft) && view.contains(r.bottomRight), isTrue);
    }

    // `/` and ⌘/Ctrl+K look for a block; ⌘/Ctrl+Enter deploys (the page
    // asks first).
    commands.clear();
    await tester.sendKeyEvent(LogicalKeyboardKey.slash);
    await primary(tester, LogicalKeyboardKey.keyK);
    await primary(tester, LogicalKeyboardKey.enter);
    expect(
      [for (final c in commands) c.$1],
      [
        FlowCommand.searchPalette,
        FlowCommand.searchPalette,
        FlowCommand.deploy,
      ],
    );

    // `?` opens the card, Esc closes it; Esc again goes to the editor.
    commands.clear();
    await withKey(
      tester,
      LogicalKeyboardKey.shiftLeft,
      () => tester.sendKeyEvent(LogicalKeyboardKey.slash),
    );
    await tester.pump();
    expect(find.byType(ShortcutCard), findsOneWidget);
    expect(find.text('Select all'), findsOneWidget);
    expect(commands, isEmpty, reason: 'Shift+/ is ?, not /');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byType(ShortcutCard), findsNothing);
    expect(commands, isEmpty);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(commands.single.$1, FlowCommand.escape);

    await tester.tap(find.byKey(const ValueKey('flow-help')));
    await tester.pump();
    expect(find.byType(ShortcutCard), findsOneWidget);
  });

  testWidgets('keys do nothing while a text field has the focus', (
    tester,
  ) async {
    screen(tester);
    final ctl = TransformationController();
    addTearDown(ctl.dispose);
    await tester.pumpWidget(
      canvas(
        controller: ctl,
        beside: const SizedBox(
          width: 200,
          height: 700,
          child: Material(child: TextField(key: ValueKey('typing'))),
        ),
      ),
    );
    // The canvas starts at x 200: block a's header.
    await tester.tapAt(const Offset(350, 56));
    await tester.pump();
    expect(selected, {'a'});

    await tester.tap(find.byKey(const ValueKey('typing')));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyEvent(LogicalKeyboardKey.slash);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await withKey(
      tester,
      LogicalKeyboardKey.shiftLeft,
      () => tester.sendKeyEvent(LogicalKeyboardKey.slash),
    );
    await primary(tester, LogicalKeyboardKey.keyA);
    await primary(tester, LogicalKeyboardKey.keyZ);
    await primary(tester, LogicalKeyboardKey.equal);
    await primary(tester, LogicalKeyboardKey.enter);
    await tester.pump();
    expect(commands, isEmpty);
    expect(moved, isEmpty);
    expect(selected, {'a'});
    expect(scaleOf(ctl), 1);
    expect(find.byType(ShortcutCard), findsNothing);
    // Space types a space: it does not turn a drag into a pan.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    final g = await drag(
      tester,
      const Offset(900, 600),
      const Offset(960, 640),
    );
    await g.up();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    // (That press was on the canvas: it took the focus from the field.)
    await tester.pumpAndSettle();

    // A press on the canvas takes the keys back.
    await tester.tapAt(const Offset(350, 56));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    expect(commands.single.$1, FlowCommand.delete);
  });

  testWidgets('Ctrl + wheel zooms about the pointer; a pinch too', (
    tester,
  ) async {
    screen(tester);
    final ctl = TransformationController();
    addTearDown(ctl.dispose);
    await tester.pumpWidget(canvas(controller: ctl));
    const at = Offset(500, 300);
    Offset onScreen(Offset canvasPoint) =>
        MatrixUtils.transformPoint(ctl.value, canvasPoint);

    final wheel = TestPointer(7, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(wheel.hover(at));
    await withKey(
      tester,
      LogicalKeyboardKey.controlLeft,
      () => tester.sendEventToBinding(wheel.scroll(const Offset(0, -120))),
    );
    expect(scaleOf(ctl), closeTo(1.6487, 1e-3));
    expect(onScreen(at), offsetMoreOrLessEquals(at, epsilon: 0.01));
    await tester.sendEventToBinding(wheel.removePointer());

    // A block is still where the pointer finds it: its header moves it.
    final head =
        tester.getTopLeft(find.byKey(const ValueKey('c'))) +
        const Offset(40, 16);
    final g = await drag(tester, head, head + const Offset(33, 0));
    await g.up();
    await tester.pumpAndSettle();
    // 33 px on the screen is 20 on the canvas at 1.6487.
    expect(moved, [('c', 420.0, 300.0)]);

    final pad = await tester.createGesture(kind: PointerDeviceKind.trackpad);
    await pad.panZoomStart(at);
    await pad.panZoomUpdate(at, scale: 0.5);
    await pad.panZoomEnd();
    await tester.pump();
    expect(scaleOf(ctl), closeTo(1.6487 / 2, 1e-3));
    await pad.panZoomStart(at);
    await pad.panZoomUpdate(at, scale: 0.01);
    await pad.panZoomEnd();
    await tester.pump();
    expect(scaleOf(ctl), FlowCanvas.minScale, reason: 'the zoom has bounds');
  });

  testWidgets('the right button opens the menu: a command, the Fields '
      'checklist, Unpin from block', (tester) async {
    screen(tester);
    await tester.pumpWidget(canvas());
    Future<void> rightClick(Offset at) async {
      await tester.tapAt(
        at,
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
    }

    final row = tester.getCenter(find.text('Remainder'));
    await rightClick(row);
    expect(find.byType(FlowMenu), findsOneWidget);
    expect(selected, {'b'}, reason: 'the block under the menu is selected');

    // A command that waits for the engine cannot be picked.
    await tester.tap(find.text('Create custom block…'));
    await tester.pumpAndSettle();
    expect(find.byType(FlowMenu), findsOneWidget);
    expect(commands, isEmpty);

    // Fields ▸: a tick pins, the menu stays; a bound field has none to take.
    await tester.tap(find.text('Fields'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Beta'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alpha'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gamma'));
    await tester.pumpAndSettle();
    expect(pins, [('b', 'p:b', true), ('b', 'p:a', false)]);
    expect(find.byType(FlowMenu), findsOneWidget);

    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();
    expect(find.byType(FlowMenu), findsNothing);
    expect(commands.single.$1, FlowCommand.copy);

    await rightClick(row);
    await tester.tap(find.text('Unpin “Row” from block'));
    await tester.pumpAndSettle();
    expect(pins.last, ('b', 'out:remainder', false));

    // On the empty canvas: Paste lands where the menu was opened.
    await rightClick(const Offset(800, 600));
    expect(selected, {'b'}, reason: 'the selection stays');
    await tester.tap(find.text('Paste'));
    await tester.pumpAndSettle();
    expect(commands.last, (FlowCommand.paste, const Offset(800, 600)));

    // While the menu is open the canvas takes no keys.
    await rightClick(const Offset(800, 600));
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    expect(commands.last.$1, FlowCommand.paste);
  });

  testWidgets('V opens the value of the row under the pointer', (tester) async {
    screen(tester);
    await tester.pumpWidget(canvas());
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.text('Input max')));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    expect(viewed, [('b', 'p:input_max')]);
  });
}
