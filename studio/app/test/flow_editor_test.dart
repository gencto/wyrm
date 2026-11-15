import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/flows/block_palette.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'flow_editor_words.dart';
import 'support/flow_app.dart';

/// The flow editor as the store makes it (studio-rules, step 1): every
/// word of its main states, and what each tool does — read from the
/// store, the fake broker's calls and the clipboard, never from the view
/// models or the callbacks, so it holds before and after the connector is
/// rewritten.
void main() {
  setUp(() => S.load(const Locale('en')));

  /// Shows [state] in [locale], checks its words, and leaves.
  Future<void> expectWords(
    WidgetTester t,
    FlowState state,
    List<String> Function() expected, {
    Locale locale = const Locale('en'),
  }) async {
    final app = await shownIn(t, state, locale: locale);
    expect(app.words(t), expected());
    if (state == .deploying) {
      // The deploy in flight answers: no timer is left behind.
      await t.pump(const Duration(seconds: 5));
      await app.settle(t);
    }
    await app.leave(t);
  }

  group('every word', () {
    final en = <FlowState, List<String> Function()>{
      .loaded: () => loadedWords,
      .level: () => levelWords,
      .pct: () => pctWords,
      .out: () => outWords,
      .valve: () => valveWords,
      .pump: () => pumpWords,
      .limit: () => limitWords,
      .sum: () => sumWords,
      .many: () => manyWords,
      .myBlocks: () => myBlocksWords,
      .tree: () => treeWords,
      .inside: () => insideWords,
      .newFlow: () => newFlowWords,
      .problem: () => problemWords,
      .scope: () => scopeWords,
      .menuBlock: () => menuBlockWords,
      .menuCanvas: () => menuCanvasWords,
      .viewer: () => viewerWords,
      .deploying: () => deployingWords,
      .writeOnly: () => writeOnlyWords,
    };
    for (final MapEntry(key: state, value: words) in en.entries) {
      testWidgets(state.name, (t) => expectWords(t, state, words));
    }
    final uk = <FlowState, List<String> Function()>{
      .loaded: () => ukLoadedWords,
      .pump: () => ukPumpWords,
      .tree: () => ukTreeWords,
      .menuBlock: () => ukMenuBlockWords,
      .myBlocks: () => ukMyBlocksWords,
      .writeOnly: () => ukWriteOnlyWords,
    };
    for (final MapEntry(key: state, value: words) in uk.entries) {
      testWidgets(
        'uk ${state.name}',
        (t) => expectWords(t, state, words, locale: const Locale('uk')),
      );
    }
  });

  /// Shows `tank` (or [id]) to [body] and leaves.
  void flowTest(
    String name,
    Future<void> Function(WidgetTester t, FlowApp app) body, {
    FlowApp Function()? make,
    String? id,
  }) => testWidgets(name, (t) async {
    final app = make?.call() ?? FlowApp();
    await app.pump(t, id: id);
    await body(t, app);
    await app.leave(t);
  });

  /// Blocks of the draft added since [before].
  Map<String, Map<String, Object?>> added(
    FlowApp app,
    Map<String, Object?> before,
  ) => {
    for (final e in app.blocks.entries)
      if (!before.containsKey(e.key)) e.key: e.value,
  };

  group('palette', () {
    Finder entry(String title) => find.descendant(
      of: find.byType(BlockPalette),
      matching: find.text(title),
    );

    flowTest('a tap on an entry adds its block', (t, app) async {
      final before = app.blocks;
      await t.tap(entry('Add'));
      await app.settle(t);
      final made = added(app, before);
      expect(made.values.single, {'type': 'add', 'x': 60.0, 'y': 60.0});
      expect(app.undo, 1);
    });

    flowTest('an entry dragged onto the canvas lands where it is let go', (
      t,
      app,
    ) async {
      final before = app.blocks;
      final to = app.emptyCanvas(t) + const Offset(400, 0);
      await app.drag(t, t.getCenter(entry('Timer')), to);
      final made = added(app, before).values.single;
      expect(made['type'], 'timer');
      // On the grid, under the pointer (the canvas is at 100 %).
      final origin = t.getTopLeft(app.block('level')) - const Offset(40, 40);
      expect(
        (made['x']! as double) - (to.dx - origin.dx),
        inInclusiveRange(-44, 0),
      );
      expect(
        (made['y']! as double) - (to.dy - origin.dy),
        inInclusiveRange(-36, 0),
      );
    });

    flowTest('the tabs switch; My blocks reads the library again', (
      t,
      app,
    ) async {
      expect(app.palette, 'blocks');
      final reads = app.calls('list_blocks').length;
      await app.tapText(t, S.current.paletteMyBlocks);
      expect(app.palette, 'my');
      expect(app.calls('list_blocks'), hasLength(reads + 1));
      expect(app.words(t), contains(S.current.myBlocksLibrary));
      await app.tapText(t, S.current.paletteTree);
      expect(app.palette, 'tree');
      expect(app.words(t), contains(S.current.findInTree));
      await app.tapText(t, S.current.paletteBlocks);
      expect(app.palette, 'blocks');
      expect(app.words(t), contains(S.current.findBlock));
    });
  });

  group('canvas', () {
    flowTest('a header dragged moves its block onto the grid', (t, app) async {
      await app.moveBy(t, 'limit', const Offset(100, 40));
      expect(app.blocks['limit'], containsPair('x', 140.0));
      expect(app.blocks['limit'], containsPair('y', 500.0));
      expect(app.undo, 1);
      expect(app.words(t), contains(S.current.draftSaved));
    });

    flowTest('an output dragged onto an input binds them', (t, app) async {
      await app.wire(t, ('limit', 'Value'), ('pct', 'Factor'));
      expect(app.edges, contains('limit.out → pct.in.k'));
      expect(app.undo, 1);
    });

    flowTest('a double click on a bound input unbinds it', (t, app) async {
      final row = t.getCenter(app.inBlock('pct', 'Input'));
      await t.tapAt(row);
      await t.pump(const Duration(milliseconds: 50));
      await t.tapAt(row);
      await app.settle(t);
      expect(app.edges, isNot(contains('level.out → pct.in')));
      expect(app.edges, contains('pct.out → out.in'));
    });

    flowTest('a bound wire picked up at its end moves to another input', (
      t,
      app,
    ) async {
      final left = t.getTopLeft(app.block('pct')).dx + 3;
      final port = Offset(left, t.getCenter(app.inBlock('pct', 'Input')).dy);
      await app.drag(t, port, t.getCenter(app.inBlock('sum', 'Input 2')));
      expect(app.edges, contains('level.out → sum.in.1'));
      expect(app.edges, isNot(contains('level.out → pct.in')));
    });

    flowTest('Delete removes the selected block and its wires', (t, app) async {
      await app.select(t, 'limit');
      await app.key(t, LogicalKeyboardKey.delete);
      expect(app.blocks.keys, isNot(contains('limit')));
      expect(app.edges, isNot(contains('limit.out → sum.in.0')));
      expect(app.undo, 1);
    });

    flowTest("the inspector's Remove removes the block", (t, app) async {
      await app.select(t, 'limit');
      await app.tapText(t, S.current.removeBlock);
      expect(app.blocks.keys, isNot(contains('limit')));
      expect(app.selected, isNull);
    });

    flowTest('a click selects one block, Shift adds one, Esc and the empty '
        'canvas clear', (t, app) async {
      await app.select(t, 'limit');
      expect(app.selection, {'limit'});
      expect(app.selected, 'limit');
      await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await t.tapAt(app.header(t, 'sum'));
      await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await app.settle(t);
      expect(app.selection, {'limit', 'sum'});
      expect(app.selected, isNull);
      expect(app.words(t), contains(S.current.fmBlocks(2)));
      await app.key(t, LogicalKeyboardKey.escape);
      expect(app.selection, isEmpty);
      await app.select(t, 'pct');
      await app.clickEmpty(t);
      expect(app.selection, isEmpty);
    });

    flowTest('Ctrl+A selects all; a marquee selects what it touches', (
      t,
      app,
    ) async {
      await app.clickEmpty(t);
      await app.primary(t, LogicalKeyboardKey.keyA);
      expect(app.selection, {
        'level',
        'pct',
        'out',
        'valve',
        'pump',
        'limit',
        'sum',
        'h1',
      });
      await app.clickEmpty(t);
      final from = t.getTopLeft(app.block('limit')) + const Offset(-20, -30);
      final to = t.getTopRight(app.block('sum')) + const Offset(-10, 10);
      await app.drag(t, from, to);
      expect(app.selection, {'limit', 'sum'});
    });

    flowTest('Tidy up of the canvas menu lays the flow out again', (
      t,
      app,
    ) async {
      List<(Object?, Object?)> places() => [
        for (final b in app.blocks.values) (b['x'], b['y']),
      ];
      final before = places();
      await app.rightClick(t, app.emptyCanvas(t));
      await app.tapAnywhere(t, S.current.fmTidy);
      expect(app.undo, 1);
      expect(places(), isNot(before));
    });
  });

  group('clipboard and history', () {
    Map<String, Object?> clip(FlowApp app) =>
        jsonDecode(app.clipboard!) as Map<String, Object?>;

    flowTest('Ctrl+C copies the selection as blocks JSON, on both '
        'clipboards', (t, app) async {
      await app.select(t, 'pct');
      await app.primary(t, LogicalKeyboardKey.keyC);
      expect(clip(app)['format'], 'wyrm-flow-blocks/1');
      expect(app.clipboard, contains('"pct"'));
      expect(app.ownClipboard, app.clipboard);
      expect(app.blocks.keys, contains('pct'));
    });

    flowTest('Ctrl+V pastes what was copied; a text that is not blocks '
        'pastes nothing', (t, app) async {
      await app.select(t, 'pct');
      await app.primary(t, LogicalKeyboardKey.keyC);
      final before = app.blocks;
      await app.primary(t, LogicalKeyboardKey.keyV);
      expect(added(app, before).values.single['type'], 'scale');
      expect(app.undo, 1);

      final now = app.blocks;
      app.clipboard = 'hello';
      await app.primary(t, LogicalKeyboardKey.keyV);
      expect(app.blocks.keys, now.keys);
    });

    flowTest('Ctrl+D duplicates; Ctrl+X cuts', (t, app) async {
      await app.select(t, 'pct');
      final before = app.blocks;
      await app.primary(t, LogicalKeyboardKey.keyD);
      expect(added(app, before).values.single['type'], 'scale');

      await app.clickEmpty(t);
      await app.select(t, 'limit');
      await app.primary(t, LogicalKeyboardKey.keyX);
      expect(app.blocks.keys, isNot(contains('limit')));
      expect(clip(app)['format'], 'wyrm-flow-blocks/1');
      expect(app.clipboard, contains('"limit"'));
    });

    flowTest('Copy of the block menu copies it', (t, app) async {
      await app.rightClick(t, app.header(t, 'pct'));
      await app.tapAnywhere(t, S.current.scCopy);
      expect(app.selection, {'pct'});
      expect(clip(app)['format'], 'wyrm-flow-blocks/1');
    });

    flowTest('Ctrl+Z undoes, Ctrl+Shift+Z and Ctrl+Y redo', (t, app) async {
      await app.moveBy(t, 'limit', const Offset(100, 40));
      await app.clickEmpty(t);
      await app.primary(t, LogicalKeyboardKey.keyZ);
      expect(app.blocks['limit'], containsPair('x', 40.0));
      expect(app.undo, 0);
      await app.primary(t, LogicalKeyboardKey.keyZ, shift: true);
      expect(app.blocks['limit'], containsPair('x', 140.0));
      await app.primary(t, LogicalKeyboardKey.keyZ);
      await app.primary(t, LogicalKeyboardKey.keyY);
      expect(app.blocks['limit'], containsPair('x', 140.0));
      expect(app.undo, 1);
    });
  });

  group('inspector', () {
    flowTest('a typed parameter goes into the config as a number', (
      t,
      app,
    ) async {
      await app.select(t, 'pct');
      await t.enterText(app.inspectorField('Factor'), '3');
      await app.settle(t);
      expect(app.blocks['pct'], containsPair('k', 3));
      expect(app.inBlock('pct', '3'), findsOneWidget);
    });

    flowTest('a typed operand goes into the values', (t, app) async {
      await app.select(t, 'sum');
      await t.enterText(app.inspectorField('Input 2'), '7');
      await app.settle(t);
      expect(app.blocks['sum']!['values'], {'in.1': 7});
    });

    flowTest('a typed argument goes into the arguments', (t, app) async {
      await app.select(t, 'pump');
      await t.enterText(app.inspectorField('speed'), '60');
      await app.settle(t);
      expect(app.blocks['pump']!['args'], {'speed': 60});
    });

    flowTest('a toggle and a choice', (t, app) async {
      await app.select(t, 'pump');
      await t.tap(find.byKey(const ValueKey('toggle-p:enabled')));
      await app.settle(t);
      expect(app.blocks['pump'], containsPair('enabled', false));

      await t.tap(
        find.descendant(of: app.inspector, matching: find.text('any')),
      );
      await t.pumpAndSettle();
      await app.tapAnywhere(t, 'change');
      expect(app.blocks['pump'], containsPair('on', 'change'));
    });

    flowTest('the link menu of a bound field goes to its source or unbinds '
        'it', (t, app) async {
      Finder link() => find
          .descendant(
            of: find
                .ancestor(
                  of: find.descendant(
                    of: app.inspector,
                    matching: find.text('Input'),
                  ),
                  matching: find.byType(Row),
                )
                .first,
            matching: find.byType(PopupMenuButton<int>),
          )
          .first;
      await app.select(t, 'pct');
      await t.tap(link());
      await t.pumpAndSettle();
      await app.tapAnywhere(t, S.current.goToSource);
      expect(app.selected, 'level');

      await app.select(t, 'pct');
      await t.tap(link());
      await t.pumpAndSettle();
      await app.tapAnywhere(t, S.current.unbind);
      expect(app.edges, isNot(contains('level.out → pct.in')));
    });

    flowTest(
      'a problem that names a block selects it',
      (t, app) async {
        await app.tapText(t, 'nodes.pct: k must be a number');
        expect(app.selected, 'pct');
      },
      make: () {
        final app = FlowApp();
        app.api.invokes['$dataflows ▸ validate'] = [
          Value.from({'ok': false, 'error': 'nodes.pct: k must be a number'}),
        ];
        return app;
      },
    );

    flowTest('a new flow is named in its field', (t, app) async {
      expect(app.store.state.flowEditor.draft?.id, '');
      await t.enterText(
        find
            .descendant(of: app.inspector, matching: find.byType(TextField))
            .first,
        'line2',
      );
      await app.settle(t);
      expect(app.store.state.flowEditor.draft?.id, 'line2');
      expect(app.words(t), contains('line2'));
    }, id: newFlow);
  });

  group('fields on the block', () {
    flowTest("the inspector's pin takes a field off the block; Fields of "
        "the block menu pins it again; Unpin of a row's menu takes one off", (
      t,
      app,
    ) async {
      await app.select(t, 'pct');
      await t.tap(find.byKey(const ValueKey('pin-p:k')));
      await app.settle(t);
      expect(app.pins('pct'), containsPair('p:k', false));
      expect(app.inBlock('pct', 'Factor'), findsNothing);

      await app.rightClick(t, app.header(t, 'pct'));
      await t.tap(find.text(S.current.fmFields));
      await t.pumpAndSettle();
      await t.tap(find.text('Factor').last);
      await t.pumpAndSettle();
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await app.settle(t);
      // Back to the type's default: the block keeps no choice for it.
      expect(app.pins('pct'), isNot(contains('p:k')));
      expect(app.inBlock('pct', 'Factor'), findsOneWidget);

      await app.rightClick(t, t.getCenter(app.inBlock('pct', 'Offset')));
      await app.tapAnywhere(t, S.current.fmUnpinField('Offset'));
      expect(app.pins('pct'), containsPair('p:b', false));
      expect(app.inBlock('pct', 'Offset'), findsNothing);
    });
  });

  group('value viewer', () {
    flowTest('V over a row opens it; Close closes it', (t, app) async {
      await app.hover(t, t.getCenter(app.inBlock('pct', 'Factor')));
      await app.key(t, LogicalKeyboardKey.keyV);
      expect(app.viewedField, 'pct/p:k');
      expect(app.words(t), contains('pct.k'));
      await t.tap(find.byTooltip(S.current.closeLabel));
      await app.settle(t);
      expect(app.viewedField, isNull);
      expect(app.words(t), isNot(contains('pct.k')));
    });

    flowTest('the eye of an inspector row opens it; Save writes the field', (
      t,
      app,
    ) async {
      await app.select(t, 'pct');
      await t.tap(
        find
            .descendant(
              of: find
                  .ancestor(
                    of: find.descendant(
                      of: app.inspector,
                      matching: find.text('Factor'),
                    ),
                    matching: find.byType(Row),
                  )
                  .first,
              matching: find.byTooltip(S.current.viewValue),
            )
            .first,
      );
      await app.settle(t);
      expect(app.viewedField, 'pct/p:k');
      await t.tap(find.byKey(const ValueKey('viewer-edit')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const ValueKey('viewer-editor')), '7');
      await t.pump();
      await t.tap(find.byKey(const ValueKey('viewer-save')));
      await app.settle(t);
      expect(app.blocks['pct'], containsPair('k', 7));
    });
  });

  group('custom blocks', () {
    flowTest('Create custom block… makes one block of the selection', (
      t,
      app,
    ) async {
      await app.select(t, 'limit');
      await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await t.tapAt(app.header(t, 'sum'));
      await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await app.settle(t);
      await app.rightClick(t, app.header(t, 'sum'));
      await app.tapAnywhere(t, S.current.fmCreateCustom);
      expect(find.text(S.current.cbTitle), findsOneWidget);
      await t.enterText(find.byKey(const ValueKey('block-name')), 'mysum');
      await t.pump();
      await t.tap(find.byKey(const ValueKey('block-create')));
      await t.pumpAndSettle();
      await app.settle(t);
      expect(app.blockDefs, {'half', 'mysum'});
      expect(app.blocks.keys, isNot(contains('limit')));
      expect(app.blocks.keys, isNot(contains('sum')));
      expect(
        [
          for (final b in app.blocks.values)
            if (b['type'] == 'block:mysum') b,
        ],
        hasLength(1),
      );
    });

    flowTest('Open inside enters an instance; Back leaves it', (t, app) async {
      app.tolerateOverflow();
      await t.tap(find.byKey(const ValueKey('open-h1')));
      await app.settle(t);
      expect(app.frames, ['half']);
      expect(app.blocks.keys, contains('div'));
      expect(app.words(t), contains(S.current.blockInputs));
      await t.tap(find.byKey(const ValueKey('flow-back')));
      await app.settle(t);
      expect(app.frames, isEmpty);
      expect(app.blocks.keys, contains('h1'));
    });

    flowTest("the inspector's Open inside enters; the flow's name in the "
        'path leaves', (t, app) async {
      app.tolerateOverflow();
      await app.select(t, 'h1');
      await t.tap(
        find.descendant(
          of: app.inspector,
          matching: find.text(S.current.openInside),
        ),
      );
      await app.settle(t);
      expect(app.frames, ['half']);
      // The path's `tank` comes before the inspector's.
      await t.tap(find.text('tank').first);
      await app.settle(t);
      expect(app.frames, isEmpty);
    });

    flowTest('Edit custom block of the block menu enters it', (t, app) async {
      app.tolerateOverflow();
      await app.rightClick(t, app.header(t, 'h1'));
      await app.tapAnywhere(t, S.current.fmEditCustom);
      expect(app.frames, ['half']);
    });

    flowTest('Save to library of My blocks puts the block', (t, app) async {
      await app.tapText(t, S.current.paletteMyBlocks);
      await app.rightClick(
        t,
        t.getCenter(find.byKey(const ValueKey('palette-type:block:half'))),
      );
      await app.tapAnywhere(t, S.current.mbSave);
      expect(app.argsOf('put_block'), [
        {
          'name': 'half',
          'def': (tankDef()['blocks']! as Map)['half'],
        },
      ]);
    });

    flowTest('a library block tapped is copied into the flow and placed', (
      t,
      app,
    ) async {
      await app.tapText(t, S.current.paletteMyBlocks);
      final before = app.blocks;
      await app.tapText(t, 'ramp');
      expect(app.argsOf('get_block'), [
        {'name': 'ramp'},
      ]);
      expect(app.blockDefs, {'half', 'ramp'});
      expect(added(app, before).values.single['type'], 'block:ramp');
    });

    flowTest('Remove from library removes it', (t, app) async {
      await app.tapText(t, S.current.paletteMyBlocks);
      await app.rightClick(
        t,
        t.getCenter(find.byKey(const ValueKey('palette-lib:ramp'))),
      );
      await app.tapAnywhere(t, S.current.mbRemoveLibrary);
      expect(app.argsOf('remove_block'), [
        {'name': 'ramp'},
      ]);
    });
  });

  group('validate, deploy, run', () {
    Map<String, Object?> lastDef(FlowApp app, String action) =>
        (app.argsOf(action).last! as Map)['def']! as Map<String, Object?>;

    flowTest('Validate asks the broker about the draft', (t, app) async {
      final before = app.calls('validate').length;
      await app.tapText(t, S.current.validate);
      expect(app.calls('validate'), hasLength(before + 1));
      expect(lastDef(app, 'validate'), containsPair('version', 4));
    });

    flowTest('Deploy is off with nothing changed; after an edit it deploys '
        'the next version at once', (t, app) async {
      await app.tapText(t, S.current.deploy);
      expect(app.calls('deploy'), isEmpty);

      await app.moveBy(t, 'limit', const Offset(100, 40));
      await app.tapText(t, S.current.deploy);
      final def = lastDef(app, 'deploy');
      expect(def['id'], 'tank');
      expect(def['version'], 4);
      expect((def['layout']! as Map)['limit'], [140, 500]);
      expect(app.words(t), contains(S.current.versionDeployed(4)));
    });

    flowTest('Ctrl+Enter asks first, then deploys', (t, app) async {
      await app.moveBy(t, 'limit', const Offset(100, 40));
      await app.primary(t, LogicalKeyboardKey.enter);
      await t.pumpAndSettle();
      expect(find.text(S.current.deployAskTitle), findsOneWidget);
      expect(app.calls('deploy'), isEmpty);
      await app.tapAnywhere(t, S.current.deploy);
      expect(lastDef(app, 'deploy'), containsPair('version', 4));
    });

    flowTest('Run of an action block triggers it on the deployed flow', (
      t,
      app,
    ) async {
      await app.select(t, 'pump');
      await t.tap(find.byKey(const ValueKey('run-in:trigger')));
      await app.settle(t);
      expect(app.argsOf('trigger'), [
        {'node': 'pump'},
      ]);
      expect(app.calls('trigger').single.key, tankKey);
    });
  });

  group('scope of a key from a wire', () {
    flowTest('a wire into a key asks its scope; Save keeps it', (
      t,
      app,
    ) async {
      await app.wire(t, ('limit', 'Value'), ('level', 'Point'));
      expect(app.scopePrompt, 'level');
      expect(app.edges, contains('limit.out → level.in.key'));
      await t.tap(find.byKey(const ValueKey('scope-save')));
      await app.settle(t);
      expect(app.scopePrompt, isNull);
      expect(
        app.blocks['level'],
        containsPair('key_scope', 'downstream/plc/**'),
      );
      expect(app.edges, contains('limit.out → level.in.key'));
    });

    flowTest('Cancel takes the wire back', (t, app) async {
      await app.wire(t, ('limit', 'Value'), ('level', 'Point'));
      await t.tap(
        find.descendant(
          of: find.byKey(const ValueKey('scope-prompt-level')),
          matching: find.text(S.current.cancel),
        ),
      );
      await app.settle(t);
      expect(app.scopePrompt, isNull);
      expect(app.edges, isNot(contains('limit.out → level.in.key')));
      expect(app.blocks['level'], isNot(contains('key_scope')));
    });
  });

  group('Tree tab', () {
    String treeRow(String key) => 'tree-$key';

    flowTest('a node opens to its points and its actions, and closes', (
      t,
      app,
    ) async {
      await app.tapText(t, S.current.paletteTree);
      await app.openTreeNode(t, plc);
      expect(
        app.api.calls.where((c) => c.op == 'list' && c.key == plc),
        hasLength(1),
      );
      app.plcPoints();
      await app.settle(t);
      expect(find.byKey(ValueKey(treeRow('key:$plc/level'))), findsOneWidget);
      expect(
        find.byKey(ValueKey(treeRow('act:$plc/start_pump'))),
        findsOneWidget,
      );
      // A config action is never offered to a flow.
      expect(find.byKey(ValueKey(treeRow('act:$plc/reset'))), findsNothing);
      await app.openTreeNode(t, plc);
      expect(find.byKey(ValueKey(treeRow('key:$plc/level'))), findsNothing);
    });

    flowTest('the search keeps what holds it', (t, app) async {
      await app.tapText(t, S.current.paletteTree);
      await app.openTreeNode(t, plc);
      app.plcPoints();
      await app.settle(t);
      await t.enterText(
        find.descendant(
          of: find.byType(BlockPalette),
          matching: find.byType(TextField),
        ),
        'valv',
      );
      await app.settle(t);
      expect(find.byKey(ValueKey(treeRow('key:$plc/valve'))), findsOneWidget);
      expect(find.byKey(ValueKey(treeRow('key:$plc/level'))), findsNothing);
    });

    flowTest('a point tapped adds a block that reads it; an action, a '
        'block that runs it', (t, app) async {
      await app.tapText(t, S.current.paletteTree);
      await app.openTreeNode(t, plc);
      app.plcPoints();
      await app.settle(t);
      var before = app.blocks;
      await t.tap(find.byKey(ValueKey(treeRow('key:$plc/level'))));
      await app.settle(t);
      expect(
        added(app, before).values.single,
        allOf(
          containsPair('type', 'subscribe'),
          containsPair('key', 'downstream/plc/level'),
        ),
      );
      before = app.blocks;
      await t.tap(find.byKey(ValueKey(treeRow('act:$plc/start_pump'))));
      await app.settle(t);
      expect(
        added(app, before).values.single,
        allOf(
          containsPair('type', 'invoke'),
          containsPair('path', 'downstream/plc'),
          containsPair('action', 'start_pump'),
        ),
      );
    });
  });

  group('live values', () {
    flowTest("the deployed flow's watch shows on its blocks", (t, app) async {
      app.api.opened['$tankKey ▸ watch']!.last.add(
        Value.from({
          't': 1762912920000000,
          'snapshot': true,
          'nodes': {
            'pct': {
              'in': {
                'in': [21.5, 0],
              },
              'out': {
                'out': [43, 0],
              },
              'params': <String, Object?>{},
            },
          },
        }),
      );
      await app.settle(t);
      expect(app.inBlock('pct', '43'), findsOneWidget);
      expect(app.inBlock('pct', '21.5'), findsOneWidget);
    });

    flowTest('a draft that differs runs as a preview; a sink shows what it '
        'would write', (t, app) async {
      // The ghost overflows the valve's row (a fault of the block view).
      app.tolerateOverflow();
      await app.select(t, 'pct');
      await t.enterText(app.inspectorField('Factor'), '3');
      await app.settle(t);
      final def =
          (app.argsOf('preview').last! as Map)['def']! as Map<String, Object?>;
      expect((def['nodes']! as Map)['pct'], {'type': 'scale', 'k': 3});
      app.api.opened['$dataflows ▸ preview']!.last.add(
        Value.from({
          't': 1762912920000000,
          'snapshot': true,
          'nodes': <String, Object?>{},
          'sinks': [
            {
              'node': 'valve',
              'op': 'set',
              'key': '$plc/valve/~set',
              'value': 64.5,
            },
          ],
        }),
      );
      await app.settle(t);
      expect(
        app.inBlock('valve', S.current.wouldWrite('64.5')),
        findsOneWidget,
      );
    });
  });
}
