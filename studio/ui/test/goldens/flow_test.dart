import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';

import 'package:ui/flows/flow_canvas.dart';
import 'package:ui/theme/common.dart';

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

  // The canvas tools, the shortcut card and the menu read `S.current`.
  setUpAll(() => S.load(const Locale('en')));

  Future<void> shoot(
    WidgetTester tester,
    String name,
    Widget page, {
    (String, String)? dragging,
    String? hover,
    Future<void> Function()? then,
    ThemeData? theme,
  }) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(frame(page, theme: theme));
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
    if (hover != null) {
      // A mouse over a bound field: its wire and source row light.
      final m = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await m.addPointer(location: Offset.zero);
      addTearDown(m.removePointer);
      await m.moveTo(
        tester.getCenter(
          find
              .descendant(
                of: find.byType(FlowCanvas),
                matching: find.text(hover),
              )
              .first,
        ),
      );
      await tester.pump();
    }
    if (then != null) {
      await then();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 300));
    }
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('$name.png'));
    await g?.up();
  }

  Finder onCanvas(String text) =>
      find.descendant(of: find.byType(FlowCanvas), matching: find.text(text));

  Future<void> rightClick(WidgetTester tester, Offset at) async {
    await tester.tapAt(
      at,
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await tester.pump(const Duration(milliseconds: 300));
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
    'a variable block: one field Value',
    (t) => shoot(t, 'flow_variable', flowVariable()),
  );
  testWidgets(
    'a bound field shows the value that comes in, its wire lit on hover',
    (t) => shoot(t, 'flow_bound_value', flowBoundValue(), hover: 'Input 1'),
  );
  testWidgets(
    'a draft preview: sinks show what they would write',
    (t) => shoot(t, 'flow_preview_sink', flowPreviewSink()),
  );
  testWidgets(
    'a case block: pairs of typed constants, − / + by a pair',
    (t) => shoot(t, 'flow_case', flowCase()),
  );
  testWidgets(
    'an operand: a typed value beside a bound one',
    (t) => shoot(t, 'flow_operand', flowOperand()),
  );
  testWidgets(
    'a long value ends in an ellipsis in every inspector cell',
    (t) => shoot(t, 'flow_long_value', flowLongOutput()),
  );
  testWidgets(
    'the value viewer: a map as a tree',
    (t) => shoot(t, 'flow_viewer_json', flowViewerJson()),
  );
  testWidgets(
    'the value viewer: a long text, numbered and wrapped',
    (t) => shoot(t, 'flow_viewer_text', flowViewerText()),
  );
  testWidgets(
    'the Tree tab with a drag in progress',
    (t) => shoot(t, 'flow_tree_drag', flowTreeDrag()),
  );
  testWidgets(
    'pins: fields taken off a block, and the Fields checklist of its menu',
    (t) => shoot(
      t,
      'flow_pins',
      flowPins(),
      then: () async {
        await rightClick(t, t.getCenter(onCanvas('case 1')));
        await t.tap(find.text('Fields'));
      },
    ),
  );
  testWidgets('a marquee in progress: the blocks it touches read selected', (
    t,
  ) async {
    late TestGesture g;
    await shoot(
      t,
      'flow_marquee',
      flowNothingSelected(),
      then: () async {
        final from =
            t.getTopLeft(find.byType(FlowCanvas)) + const Offset(300, 30);
        g = await t.startGesture(from, kind: PointerDeviceKind.mouse);
        for (var i = 1; i <= 8; i++) {
          await g.moveTo(from + Offset(70.0 * i, 72.0 * i));
          await t.pump(const Duration(milliseconds: 16));
        }
      },
    );
    await g.up();
  });
  testWidgets(
    'several blocks selected, with their context menu',
    (t) => shoot(
      t,
      'flow_selection_menu',
      flowSelection(),
      then: () => rightClick(t, t.getCenter(onCanvas('Expression'))),
    ),
  );
  testWidgets('the shortcut card, with the glyphs of macOS', (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await shoot(
        t,
        'flow_shortcuts',
        flowNothingSelected(),
        then: () => t.tap(find.byKey(const ValueKey('flow-help'))),
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
  testWidgets(
    'the shortcut card, with Ctrl, Alt and Shift',
    (t) => shoot(
      t,
      'flow_shortcuts_ctrl',
      flowNothingSelected(),
      then: () async {
        await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await t.sendKeyEvent(LogicalKeyboardKey.slash);
        await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      },
    ),
  );
  testWidgets(
    'the value viewer in its Edit mode: a JSON editor, Save and Cancel',
    (t) => shoot(
      t,
      'flow_viewer_edit',
      flowViewerEdit(),
      then: () => t.tap(find.byKey(const ValueKey('viewer-edit'))),
    ),
  );
  testWidgets(
    'the value viewer of a bound field: read only, with the reason',
    (t) => shoot(t, 'flow_viewer_locked', flowViewerEdit(locked: true)),
  );

  // Wave 2 (flow-editor.md §17–§20, ADR 0040).
  testWidgets(
    'a subscribe with a bound key: the Scope row, the Error output',
    (t) => shoot(t, 'flow_key_scope', flowKeyScope()),
  );
  testWidgets(
    'the scope asked in place when a key gets a wire',
    (t) => shoot(t, 'flow_scope_prompt', flowKeyScope(asking: true)),
  );
  testWidgets('the Tree tab: values, actions, and a drag in progress', (
    t,
  ) async {
    late TestGesture g;
    await shoot(
      t,
      'flow_tree_tab',
      flowTreeTab(),
      then: () async {
        // An action dragged out of the tree, not let go yet.
        final from = t.getCenter(find.text('stop_pump'));
        final to = t.getCenter(find.byType(FlowCanvas)) + const Offset(80, 120);
        g = await t.startGesture(from, kind: PointerDeviceKind.mouse);
        for (var i = 1; i <= 8; i++) {
          await g.moveTo(Offset.lerp(from, to, i / 8)!);
          await t.pump(const Duration(milliseconds: 16));
        }
      },
    );
    await g.up();
  });
  testWidgets(
    'an action block: Target, Arguments, Behaviour, Events, State',
    (t) => shoot(t, 'flow_action_block', flowActionBlock()),
  );
  testWidgets(
    'an action block with an unbound trigger: Run, and why it is off',
    (t) => shoot(
      t,
      'flow_action_run',
      flowActionBlock(
        button: true,
        runReason:
            'Deploy first: Run acts on the deployed version, and the draft '
            'differs from it',
        preview: true,
      ),
    ),
  );
  testWidgets(
    'a custom block instance, and the My blocks tab',
    (t) => shoot(t, 'flow_custom_instance', flowCustomInstance()),
  );
  testWidgets(
    'My blocks: the menu of a block of this flow',
    (t) => shoot(
      t,
      'flow_my_blocks',
      flowCustomInstance(),
      then: () => rightClick(t, t.getCenter(find.text('mean2').first)),
    ),
  );
  testWidgets(
    'the inside of a custom block: the path, Back, inputs and outputs',
    (t) => shoot(t, 'flow_custom_inside', flowCustomInside()),
  );
  testWidgets(
    'Create custom block: the name and the ports of a selection',
    (t) => shoot(
      t,
      'flow_custom_dialog',
      flowCustomCreate(),
      then: () async {
        await rightClick(t, t.getCenter(onCanvas('a').first));
        await t.tap(find.textContaining('Create custom block'));
        await t.pump(const Duration(milliseconds: 300));
      },
    ),
  );
  testWidgets(
    'the table window: every row in a grid, cells by type, editable',
    (t) => shoot(t, 'flow_viewer_table', flowViewerTable()),
  );
  testWidgets(
    'the table window in the light theme',
    (t) => shoot(
      t,
      'flow_viewer_table_light',
      flowViewerTable(),
      theme: lightTheme(),
    ),
  );
  testWidgets(
    'the table window with a cell in its editor and a change to save',
    (t) => shoot(
      t,
      'flow_viewer_table_edit',
      flowViewerTable(),
      then: () async {
        await t.tap(find.byKey(const ValueKey('table-cell-1-2')));
        await t.pump(const Duration(milliseconds: 400));
        await t.sendKeyEvent(LogicalKeyboardKey.delete);
        await t.pump();
        await t.tap(find.byKey(const ValueKey('table-cell-0-2')));
        await t.pump(const Duration(milliseconds: 400));
        await t.sendKeyEvent(LogicalKeyboardKey.enter);
        await t.pump();
      },
    ),
  );
  testWidgets(
    'a text of several lines: its first line and a mark with the count',
    (t) => shoot(t, 'flow_lines_mark', flowCsvLines()),
  );
}
