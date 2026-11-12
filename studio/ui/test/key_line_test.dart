import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/indicators/key_line.dart';
import 'package:ui/trees/node_tree.dart';
import 'package:ui/trees/tree_row.dart';

import 'frames/harness.dart';

/// The path line of Explorer (docs/design/specs/explorer.md §3.1): the
/// parents are links, `wy`, the site and the node on screen are not.
void main() {
  const key = 'wy/plant/downstream/s7/plc1/cpu';
  const links = {
    'wy/plant/downstream',
    'wy/plant/downstream/s7',
    'wy/plant/downstream/s7/plc1',
  };

  Future<List<String>> pump(WidgetTester tester, {VoidCallback? onCopy}) async {
    final opened = <String>[];
    await tester.pumpWidget(
      frame(
        Center(
          child: KeyLine(
            keyName: key,
            links: links,
            onOpen: opened.add,
            onCopy: onCopy,
          ),
        ),
      ),
    );
    return opened;
  }

  Finder crumb(String k) => find.byKey(ValueKey('crumb:$k'));

  testWidgets('a click on a segment opens the node of that segment', (
    tester,
  ) async {
    final opened = await pump(tester);
    await tester.tap(crumb('wy/plant/downstream/s7'));
    await tester.tap(crumb('wy/plant/downstream'));
    await tester.tap(crumb('wy/plant/downstream/s7/plc1'));
    expect(opened, [
      'wy/plant/downstream/s7',
      'wy/plant/downstream',
      'wy/plant/downstream/s7/plc1',
    ]);
  });

  testWidgets('wy, the site and the last segment are plain text', (
    tester,
  ) async {
    await pump(tester);
    expect(crumb('wy'), findsNothing);
    expect(crumb('wy/plant'), findsNothing);
    expect(crumb(key), findsNothing);
    for (final s in ['downstream', 's7', 'plc1']) {
      expect(find.text(s), findsOneWidget);
    }
  });

  testWidgets('hover: a pointer cursor and an underline', (tester) async {
    await pump(tester);
    final target = crumb('wy/plant/downstream/s7');
    Text label() =>
        tester.widget(find.descendant(of: target, matching: find.byType(Text)));
    expect(label().style?.decoration, isNot(TextDecoration.underline));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(target));
    await tester.pump();
    expect(label().style?.decoration, TextDecoration.underline);
    expect(
      RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
      SystemMouseCursors.click,
    );
  });

  testWidgets('keyboard: Tab reaches each link in order, Enter opens it', (
    tester,
  ) async {
    final opened = await pump(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(opened, ['wy/plant/downstream/s7']);
    final label = tester.widget<Text>(
      find.descendant(
        of: crumb('wy/plant/downstream/s7'),
        matching: find.byType(Text),
      ),
    );
    expect(label.style?.decoration, TextDecoration.underline);
  });

  testWidgets('Copy is the button, not a segment', (tester) async {
    var copied = 0;
    final opened = await pump(tester, onCopy: () => copied++);
    await tester.tap(find.byTooltip('Copy key'));
    expect(copied, 1);
    expect(opened, isEmpty);
  });

  testWidgets('a long key with links ends in an ellipsis, Copy stays', (
    tester,
  ) async {
    const seg = 'supply_air_temperature_controller_north_wing_f2';
    const long = 'wy/plant/downstream/modbus/$seg/$seg/temp';
    await tester.pumpWidget(
      frame(
        Center(
          child: SizedBox(
            width: 300,
            child: KeyLine(
              keyName: long,
              links: const {
                'wy/plant/downstream',
                'wy/plant/downstream/modbus',
                'wy/plant/downstream/modbus/$seg',
                'wy/plant/downstream/modbus/$seg/$seg',
              },
              onOpen: (_) {},
              onCopy: () {},
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    final copy = find.byTooltip('Copy key');
    expect(copy, findsOneWidget);
    final right = tester.getTopRight(copy).dx;
    expect(
      right,
      lessThanOrEqualTo(tester.getTopRight(find.byType(KeyLine)).dx),
    );
  });

  testWidgets('without links the line is the plain key', (tester) async {
    await tester.pumpWidget(frame(const Center(child: KeyLine(keyName: key))));
    expect(find.text(key, findRichText: true), findsOneWidget);
  });

  testWidgets('the tree scrolls to a row selected from outside it', (
    tester,
  ) async {
    List<TreeRowVm> rows(String selected) => [
      for (var i = 0; i < 60; i++)
        TreeRowVm(
          id: 'n$i',
          name: 'node$i',
          depth: 0,
          icon: 'node_folder',
          selected: 'n$i' == selected,
        ),
    ];
    Widget tree(String selected) => frame(
      Row(
        children: [
          NodeTree(
            label: 'TREE',
            rows: rows(selected),
            onTap: (_) {},
            onToggle: (_) {},
          ),
        ],
      ),
    );
    await tester.pumpWidget(tree('n0'));
    expect(find.text('node50'), findsNothing);
    await tester.pumpWidget(tree('n50'));
    await tester.pump();
    await tester.pump();
    expect(find.text('node50'), findsOneWidget);
    // And back up.
    await tester.pumpWidget(tree('n1'));
    await tester.pump();
    await tester.pump();
    expect(find.text('node1'), findsOneWidget);
  });
}
