import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:ui/flows/block_palette.dart';
import 'package:ui/flows/custom_block_dialog.dart';
import 'package:ui/flows/field_inspector.dart';
import 'package:ui/flows/flow_block_view.dart';
import 'package:ui/flows/flow_canvas.dart';
import 'package:ui/flows/scope_prompt.dart';
import 'package:ui/pages/flow_editor_page.dart';
import 'package:ui/trees/tree_row.dart';

import 'frames/flow.dart';
import 'frames/harness.dart';

/// Wave 2 of the flow editor (flow-editor.md §17–§20): the scope's prompt,
/// the Tree tab's rows, a writable point's Read or Write, the inspector's
/// Run button, period and the toggle that asks first, a block's `Open
/// inside`, and the create-custom-block dialog.
void main() {
  setUpAll(() => S.load(const Locale('en')));

  Future<void> show(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(frame(child));
    await tester.pump(const Duration(milliseconds: 300));
  }

  group('the scope prompt', () {
    const vm = ScopePromptVm(
      block: 'level',
      row: 'p:key_scope',
      title: 'This block may read keys under',
      value: 'downstream/modbus/line1/**',
      note: 'A key that comes on the wire is read only inside this scope.',
      suggestions: ['downstream/modbus/line1/**', 'storage/**'],
    );

    testWidgets('starts with the suggestion and saves it', (tester) async {
      final saved = <String>[];
      await show(
        tester,
        Center(
          child: ScopePrompt(vm: vm, onSave: saved.add, onCancel: () {}),
        ),
      );
      expect(find.text('downstream/modbus/line1/**'), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('scope-save')));
      expect(saved, ['downstream/modbus/line1/**']);
    });

    testWidgets('a refused scope says why and is not saved; a chip fills '
        'the field; Esc cancels', (tester) async {
      final saved = <String>[];
      var cancelled = 0;
      await show(
        tester,
        Center(
          child: ScopePrompt(
            vm: vm,
            onSave: saved.add,
            onCancel: () => cancelled++,
            validate: (s) => s.startsWith('sys') ? 'Not in sys' : null,
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('scope-field')),
        'sys/**',
      );
      await tester.pump();
      expect(find.text('Not in sys'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('scope-save')));
      await tester.testTextInput.receiveAction(TextInputAction.done);
      expect(saved, isEmpty);

      await tester.tap(find.text('storage/**'));
      await tester.pump();
      expect(find.text('Not in sys'), findsNothing);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      expect(saved, ['storage/**']);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(cancelled, 1);
    });

    testWidgets('the canvas draws it on the field, and the pencil of the '
        'Scope row asks again', (tester) async {
      final asked = <(String, String)>[];
      final page = flowKeyScope(asking: true);
      await show(
        tester,
        FlowCanvas(
          blocks: page.blocks,
          wires: page.wires,
          actions: FlowBlockActions(
            onSelect: (_) {},
            onBind: (_, _, _) {},
            onRebind: (_, _, _, _) {},
            onUnbind: (_, _) {},
            onDropEntry: (_, _, _) {},
            onResize: (_, {required add}) {},
            onRowAction: (b, r) => asked.add((b, r)),
          ),
          onClear: () {},
          onMove: (_, {required nudge}) {},
          onDrop: (_, _, _) {},
          prompt: page.prompt,
        ),
      );
      final prompt = tester.getRect(find.byType(ScopePrompt));
      final row = tester.getRect(find.text('Scope'));
      expect(prompt.top, greaterThan(row.bottom - 1));
      expect(prompt.top - row.bottom, lessThan(24));

      await tester.tap(
        find.byKey(const ValueKey('row-action-level-p:key_scope')),
      );
      expect(asked, [('level', 'p:key_scope')]);
    });
  });

  group('the Tree tab', () {
    const rows = [
      TreeRowVm(
        id: 'n',
        name: 'tcp-tank',
        depth: 0,
        hasChildren: true,
        expanded: true,
      ),
      TreeRowVm(
        id: 'n/~act/stop',
        name: 'stop_pump',
        depth: 1,
        tag: 'ACT',
        ember: true,
        value: '1 in',
        drag: 'act:n/stop',
      ),
      TreeRowVm(
        id: 'n/level',
        name: 'level',
        depth: 1,
        tag: '.0',
        value: '92.6',
        drag: 'key:n/level',
      ),
    ];

    testWidgets('a node opens or closes; a leaf or an action is added by a '
        'tap; the filter goes to whoever makes the rows', (tester) async {
      final picked = <String>[];
      final toggled = <String>[];
      final queries = <String>[];
      await show(
        tester,
        SizedBox(
          width: 260,
          child: BlockPalette(
            tabs: const [],
            tab: 'tree',
            onTab: (_) {},
            entries: const [],
            onPick: picked.add,
            tree: rows,
            onTreeToggle: toggled.add,
            onQuery: queries.add,
          ),
        ),
      );
      expect(find.text('ACT'), findsOneWidget);
      expect(find.text('92.6'), findsOneWidget);
      await tester.tap(find.text('tcp-tank'));
      await tester.tap(find.text('level'));
      await tester.tap(find.text('stop_pump'));
      expect(toggled, ['n']);
      expect(picked, ['key:n/level', 'act:n/stop']);
      await tester.enterText(find.byType(TextField), 'lev');
      expect(queries, ['lev']);
    });

    testWidgets('an empty tab says so', (tester) async {
      await show(
        tester,
        SizedBox(
          width: 260,
          child: BlockPalette(
            tabs: const [],
            tab: 'tree',
            onTab: (_) {},
            entries: const [],
            onPick: (_) {},
            tree: const [],
            empty: 'Nothing to show here.',
          ),
        ),
      );
      expect(find.text('Nothing to show here.'), findsOneWidget);
    });

    Future<List<(String, double, double)>> dropLevel(
      WidgetTester tester, {
      required Set<String> writable,
      String? pick,
    }) async {
      final dropped = <(String, double, double)>[];
      final base = flowTreeTab();
      await show(
        tester,
        FlowEditorPage(
          flowsLabel: 'Flows',
          flowLabel: 'line',
          state: '',
          validateLabel: 'Validate',
          deployLabel: 'Deploy',
          onValidate: () {},
          onClose: () {},
          onFlows: () {},
          onLogo: () {},
          paletteTabs: base.paletteTabs,
          paletteTab: 'tree',
          onPaletteTab: (_) {},
          palette: const [],
          onPick: (_) {},
          tree: rows,
          blocks: const [],
          wires: const [],
          blockActions: base.blockActions,
          onClear: () {},
          onMove: (_, {required nudge}) {},
          onDrop: (e, x, y) => dropped.add((e, x, y)),
          inspectorFooter: const [],
          onFieldChanged: (_, _) {},
          onFieldUnbind: (_) {},
          onFieldBind: (_, _) {},
          onProblem: (_) {},
          writable: writable,
        ),
      );
      final from = tester.getCenter(find.text('level'));
      final to = tester.getCenter(find.byType(FlowCanvas));
      final g = await tester.startGesture(from, kind: PointerDeviceKind.mouse);
      for (var i = 1; i <= 6; i++) {
        await g.moveTo(Offset.lerp(from, to, i / 6)!);
        await tester.pump(const Duration(milliseconds: 16));
      }
      await g.up();
      await tester.pumpAndSettle();
      if (pick != null) {
        await tester.tap(find.text(pick));
        await tester.pumpAndSettle();
      }
      return dropped;
    }

    testWidgets('a point dropped on the canvas reads it', (tester) async {
      final dropped = await dropLevel(tester, writable: const {});
      expect(dropped.single.$1, 'key:n/level');
    });

    testWidgets('a writable point asks Read or Write', (tester) async {
      final dropped = await dropLevel(
        tester,
        writable: const {'key:n/level'},
        pick: 'Write',
      );
      expect(dropped.single.$1, 'set:n/level');
    });

    testWidgets('…and Read reads it', (tester) async {
      final dropped = await dropLevel(
        tester,
        writable: const {'key:n/level'},
        pick: 'Read',
      );
      expect(dropped.single.$1, 'key:n/level');
    });

    testWidgets('…and with Alt held it writes at once', (tester) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      final dropped = await dropLevel(tester, writable: const {'key:n/level'});
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      expect(find.text('Write'), findsNothing);
      expect(dropped.single.$1, 'set:n/level');
    });
  });

  group('the action block in the inspector', () {
    Future<List<String>> inspector(
      WidgetTester tester,
      List<InspectorRowVm> rows, {
      List<String>? ran,
    }) async {
      final changed = <String>[];
      await show(
        tester,
        SizedBox(
          width: 340,
          child: FieldInspector(
            footer: const [],
            rows: rows,
            onChanged: (id, v) => changed.add('$id=$v'),
            onUnbind: (_) {},
            onBind: (_, _) {},
            onProblem: (_) {},
            onRun: ran?.add,
          ),
        ),
      );
      return changed;
    }

    testWidgets('rows stand under their groups, each heading once', (
      tester,
    ) async {
      await inspector(tester, flowActionBlock().inspectorRows);
      for (final g in ['TARGET', 'ARGUMENTS', 'BEHAVIOUR', 'EVENTS']) {
        expect(find.text(g), findsOneWidget);
      }
      // An event reads when it fired and what it said, whole.
      await tester.scrollUntilVisible(
        find.text('13:58:02 · busy: queue full'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('13:58:02 · busy: queue full'), findsOneWidget);
    });

    testWidgets('an unbound trigger is a Run button', (tester) async {
      final ran = <String>[];
      await inspector(tester, const [
        InspectorRowVm(
          id: 'in:trigger',
          name: 'Trigger',
          editor: FieldEditorVm.run,
          value: 'Run',
        ),
      ], ran: ran);
      await tester.tap(find.byKey(const ValueKey('run-in:trigger')));
      expect(ran, ['in:trigger']);
    });

    testWidgets('off, Run says why and does nothing', (tester) async {
      final ran = <String>[];
      await inspector(tester, const [
        InspectorRowVm(
          id: 'in:trigger',
          name: 'Trigger',
          editor: FieldEditorVm.run,
          value: 'Run',
          disabledReason: 'Deploy the flow first',
        ),
      ], ran: ran);
      expect(find.text('Deploy the flow first'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('run-in:trigger')),
        warnIfMissed: false,
      );
      expect(ran, isEmpty);
    });

    // A CSV typed in the value viewer (spec 06 0.2.30): the row keeps its
    // lines, and a key typed there keeps them too.
    testWidgets('a text of several lines keeps its lines', (tester) async {
      final changed = await inspector(tester, const [
        InspectorRowVm(
          id: 'in:in',
          name: 'Input',
          editor: FieldEditorVm.text,
          value: 'a,b\n1,2',
        ),
      ]);
      expect(find.byKey(const ValueKey('text-editor-lines')), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'a,b\n1,2\n3,4');
      expect(changed, ['in:in=a,b\n1,2\n3,4']);
    });

    testWidgets('a one-line text stays a one-line field', (tester) async {
      await inspector(tester, const [
        InspectorRowVm(
          id: 'in:in',
          name: 'Input',
          editor: FieldEditorVm.text,
          value: '1,1,1,1',
        ),
      ]);
      expect(find.byKey(const ValueKey('text-editor-lines')), findsNothing);
    });

    testWidgets('a period reads in its largest whole unit and writes '
        'milliseconds', (tester) async {
      final changed = await inspector(tester, const [
        InspectorRowVm(
          id: 'p:interval_ms',
          name: 'Every',
          editor: FieldEditorVm.duration,
          value: '300000',
        ),
      ]);
      expect(find.text('5'), findsOneWidget);
      expect(find.text('min'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '2');
      expect(changed, ['p:interval_ms=120000']);
    });

    testWidgets('Run on start asks first, with the warning; Cancel leaves '
        'it off', (tester) async {
      const row = InspectorRowVm(
        id: 'p:run_on_start',
        name: 'Run on start',
        editor: FieldEditorVm.toggle,
        value: 'false',
        confirm: ('Run on every start?', 'WARNING: true runs this command.'),
      );
      final changed = await inspector(tester, const [row]);
      await tester.tap(find.byKey(const ValueKey('toggle-p:run_on_start')));
      await tester.pumpAndSettle();
      expect(find.text('WARNING: true runs this command.'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(changed, isEmpty);

      await tester.tap(find.byKey(const ValueKey('toggle-p:run_on_start')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Turn on'));
      await tester.pumpAndSettle();
      expect(changed, ['p:run_on_start=true']);
    });
  });

  group('custom blocks', () {
    testWidgets('an instance opens its inside from its link row', (
      tester,
    ) async {
      final opened = <String>[];
      final page = flowCustomInstance();
      await show(
        tester,
        FlowCanvas(
          blocks: page.blocks,
          wires: page.wires,
          actions: FlowBlockActions(
            onSelect: (_) {},
            onBind: (_, _, _) {},
            onRebind: (_, _, _, _) {},
            onUnbind: (_, _) {},
            onDropEntry: (_, _, _) {},
            onResize: (_, {required add}) {},
            onOpen: opened.add,
          ),
          onClear: () {},
          onMove: (_, {required nudge}) {},
          onDrop: (_, _, _) {},
        ),
      );
      await tester.tap(find.byKey(const ValueKey('open-mean21')));
      expect(opened, ['mean21']);
    });

    testWidgets('inside a block the path links back, level by level', (
      tester,
    ) async {
      final back = <int>[];
      final base = flowCustomInside();
      await show(
        tester,
        FlowEditorPage(
          flowsLabel: 'Flows',
          flowLabel: 'line',
          state: '',
          validateLabel: 'Validate',
          deployLabel: 'Deploy',
          deployReason: 'Go back to the flow to deploy',
          onValidate: () {},
          onClose: () {},
          onFlows: () {},
          onLogo: () {},
          paletteTabs: base.paletteTabs,
          paletteTab: 'blocks',
          onPaletteTab: (_) {},
          palette: const [],
          onPick: (_) {},
          blocks: const [],
          wires: const [],
          blockActions: base.blockActions,
          onClear: () {},
          onMove: (_, {required nudge}) {},
          onDrop: (_, _, _) {},
          inspectorFooter: const [],
          onFieldChanged: (_, _) {},
          onFieldUnbind: (_) {},
          onFieldBind: (_, _) {},
          onProblem: (_) {},
          crumbs: const ['outer', 'inner'],
          onBack: back.add,
        ),
      );
      await tester.tap(find.byKey(const ValueKey('flow-back')));
      await tester.tap(find.text('outer'));
      await tester.tap(find.text('line'));
      expect(back, [1, 1, 2]);
    });

    testWidgets('the dialog hands back the names typed and the defaults; a '
        'refused name keeps Create off', (tester) async {
      CustomBlockResult? made;
      await show(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              made = await CustomBlockDialog.ask(
                context,
                vm: const CustomBlockDialogVm(
                  title: 'Create custom block',
                  note: '2 blocks become one block of this flow.',
                  name: 'block1',
                  inputs: [
                    BlockPortVm(name: 'sum_0', detail: '← a.out'),
                    BlockPortVm(name: 'sum_1', detail: '← b.out'),
                  ],
                  outputs: [BlockPortVm(name: 'half', detail: '→ mean.in')],
                ),
                validate: (r) => r.name.contains(' ') ? 'Bad name' : null,
              );
            },
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final fields = find.descendant(
        of: find.byType(CustomBlockDialog),
        matching: find.byType(TextField),
      );
      // name, description, (input, default) × 2, output
      expect(fields, findsNWidgets(7));
      await tester.enterText(fields.at(0), 'my block');
      await tester.pump();
      expect(find.text('Bad name'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('block-create')));
      await tester.pumpAndSettle();
      expect(made, isNull);

      await tester.enterText(fields.at(0), 'mean2');
      await tester.enterText(fields.at(1), 'The mean of two');
      await tester.enterText(fields.at(2), 'first');
      await tester.enterText(fields.at(5), '0');
      await tester.enterText(fields.at(6), 'out');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('block-create')));
      await tester.pumpAndSettle();
      expect(made!.name, 'mean2');
      expect(made!.description, 'The mean of two');
      expect(made!.inputs, ['first', 'sum_1']);
      expect(made!.outputs, ['out']);
      expect(made!.defaults, {'sum_1': '0'});
    });

    testWidgets('a block of the palette has its menu; an item that is off '
        'does nothing', (tester) async {
      final menu = <(String, String)>[];
      final page = flowCustomInstance();
      await show(
        tester,
        SizedBox(
          width: 260,
          child: BlockPalette(
            tabs: const [],
            tab: 'my',
            onTab: (_) {},
            entries: page.palette,
            onPick: (_) {},
            onMenu: (e, i) => menu.add((e, i)),
          ),
        ),
      );
      Future<void> pick(String item) async {
        await tester.tapAt(
          tester.getCenter(find.text('mean2')),
          kind: PointerDeviceKind.mouse,
          buttons: kSecondaryMouseButton,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(item), warnIfMissed: false);
        await tester.pumpAndSettle();
      }

      await pick('Save to library');
      await pick('Delete');
      expect(menu, [('type:block:mean2', 'save')]);
    });
  });
}
