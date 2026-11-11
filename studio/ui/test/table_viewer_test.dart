import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:ui/flows/flow_block_view.dart';
import 'package:ui/indicators/lines_text.dart';
import 'package:ui/overlays/value_viewer.dart';
import 'package:ui/tables/table_edits.dart';

import 'frames/harness.dart';

/// The table window of the value viewer (owner request 2026-11-11,
/// docs/studio.md §6.8): all rows in a grid that builds only what is in
/// view, the cells by type, a filter; a typed table edits in place within
/// the bounds of ADR 0044; a wired one is read only; a CSV text shows "As
/// table" by the block's rules; a text of several lines says so on one line.
void main() {
  setUpAll(() => S.load(const Locale('en')));

  late List<String> saved;
  var closed = 0;

  setUp(() {
    saved = [];
    closed = 0;
  });

  TableDataVm pumps() => TableDataVm(
    ['name', 'kw', 'on', 'meta'],
    [
      ['pump', 3, true, null],
      [
        'fan',
        7.5,
        false,
        {'zone': 'A'},
      ],
    ],
  );

  Future<void> show(
    WidgetTester tester,
    ValueViewerVm vm, {
    bool canSave = true,
    ViewerTables? tables,
  }) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      frame(
        Stack(
          children: [
            Positioned.fill(
              child: ValueViewer(
                vm: vm,
                onClose: () => closed++,
                onSave: canSave ? saved.add : null,
                tables: tables,
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }

  ValueViewerVm typed(TableDataVm t, {String? locked}) => ValueViewerVm(
    title: 'table1.value',
    type: 'table',
    size: '${t.rows.length} rows · ${t.columns.length} columns',
    content: TableContentVm(t),
    copy: t.toJsonText(),
    edit: locked == null
        ? ViewerEditVm(kind: .table, text: t.toJsonText(), table: t)
        : null,
    locked: locked,
  );

  Finder cell(int r, int c) => find.byKey(ValueKey('table-cell-$r-$c'));

  Future<void> key(WidgetTester tester, LogicalKeyboardKey k) async {
    await tester.sendKeyEvent(k);
    await tester.pump();
  }

  testWidgets('10 000 rows build; only the rows in view are built', (
    tester,
  ) async {
    final big = TableDataVm(
      ['n', 'name'],
      [
        for (var i = 0; i < 10000; i++) [i, 'row $i'],
      ],
    );
    final started = DateTime.now();
    await show(tester, typed(big, locked: 'Read only.'), canSave: false);
    expect(
      DateTime.now().difference(started),
      lessThan(const Duration(seconds: 5)),
    );
    expect(find.byKey(const ValueKey('table-row-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('table-row-9999')), findsNothing);
    // Scrolled to the end, the last row is built and the first is gone.
    await tester.drag(
      find.byKey(const ValueKey('table-rows')),
      const Offset(0, -300000),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('table-row-9999')), findsOneWidget);
    expect(find.byKey(const ValueKey('table-row-0')), findsNothing);
    expect(find.text('10000'), findsOneWidget, reason: 'the row number');
    expect(tester.takeException(), isNull);
  });

  testWidgets('cells by type; the filter counts what it keeps', (
    tester,
  ) async {
    await show(tester, typed(pumps(), locked: 'Read only.'), canSave: false);
    expect(find.text('null'), findsOneWidget);
    expect(find.text('{"zone":"A"}'), findsOneWidget);
    final kw = tester.widget<Text>(
      find.descendant(of: cell(0, 1), matching: find.text('3')),
    );
    expect(kw.textAlign, TextAlign.right);
    await tester.enterText(find.byKey(const ValueKey('table-filter')), 'FAN');
    await tester.pump();
    expect(find.text('1 of 2 rows'), findsOneWidget);
    expect(find.byKey(const ValueKey('table-row-0')), findsNothing);
    expect(find.byKey(const ValueKey('table-row-1')), findsOneWidget);
  });

  testWidgets('a wired table is read only and says why', (tester) async {
    await show(
      tester,
      typed(pumps(), locked: 'Read only: a wire feeds this field.'),
    );
    expect(find.byKey(const ValueKey('table-add-row')), findsNothing);
    expect(find.byKey(const ValueKey('viewer-edit')), findsNothing);
    expect(find.text('Read only: a wire feeds this field.'), findsOneWidget);
    await tester.tap(cell(0, 0));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(cell(0, 0));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(cell(0, 0));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('table-cell-editor')), findsNothing);
  });

  testWidgets('a cell edits in place and keeps its type; Save writes JSON', (
    tester,
  ) async {
    await show(tester, typed(pumps()));
    // Double click on kw of pump, type, Enter: a number stays a number.
    await tester.tap(cell(0, 1));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(cell(0, 1));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('table-cell-editor')), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('table-cell-editor')),
      '4.5',
    );
    await key(tester, LogicalKeyboardKey.enter);
    // Enter moved down to fan; typing starts its edit, Esc drops it.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyX, character: 'x');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyX);
    await tester.pump();
    expect(find.byKey(const ValueKey('table-cell-editor')), findsOneWidget);
    await key(tester, LogicalKeyboardKey.escape);
    expect(find.byKey(const ValueKey('table-cell-editor')), findsNothing);
    // A number cell that does not read as one becomes a text.
    await key(tester, LogicalKeyboardKey.enter);
    await tester.enterText(
      find.byKey(const ValueKey('table-cell-editor')),
      'n/a',
    );
    await key(tester, LogicalKeyboardKey.tab);
    // Tab moved to `on`; Delete empties it.
    await key(tester, LogicalKeyboardKey.delete);
    expect(find.byKey(const ValueKey('viewer-save')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('viewer-save')));
    await tester.pump();
    expect(saved, hasLength(1));
    final v = jsonDecode(saved.single) as Map<String, Object?>;
    expect(v['columns'], ['name', 'kw', 'on', 'meta']);
    expect(v['rows'], [
      {'name': 'pump', 'kw': 4.5, 'on': true, 'meta': null},
      {
        'name': 'fan',
        'kw': 'n/a',
        'on': null,
        'meta': {'zone': 'A'},
      },
    ]);
    expect(find.byKey(const ValueKey('viewer-save')), findsNothing);
  });

  testWidgets('Esc drops a cell edit, then the changes, then the window', (
    tester,
  ) async {
    await show(tester, typed(pumps()));
    await tester.tap(cell(0, 0));
    await tester.pump(const Duration(milliseconds: 400));
    await key(tester, LogicalKeyboardKey.delete);
    expect(find.byKey(const ValueKey('viewer-save')), findsOneWidget);
    await key(tester, LogicalKeyboardKey.enter);
    expect(find.byKey(const ValueKey('table-cell-editor')), findsOneWidget);
    await key(tester, LogicalKeyboardKey.escape);
    expect(find.byKey(const ValueKey('table-cell-editor')), findsNothing);
    expect(closed, 0);
    await key(tester, LogicalKeyboardKey.escape);
    expect(find.byKey(const ValueKey('viewer-save')), findsNothing);
    expect(closed, 0);
    expect(saved, isEmpty);
    await key(tester, LogicalKeyboardKey.escape);
    expect(closed, 1);
  });

  testWidgets('rows and columns are added, renamed and removed', (
    tester,
  ) async {
    await show(tester, typed(TableDataVm.empty()));
    expect(find.text(S.current.tableNoColumnsEdit), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('table-add-column')));
    await tester.pump();
    await tester.pump();
    // A new column is named at once.
    expect(find.byKey(const ValueKey('table-name-editor')), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('table-name-editor')),
      'level',
    );
    await key(tester, LogicalKeyboardKey.enter);
    await tester.tap(find.byKey(const ValueKey('table-add-row')));
    await tester.pump();
    await tester.tap(cell(0, 0));
    await tester.pump(const Duration(milliseconds: 400));
    await key(tester, LogicalKeyboardKey.enter);
    await tester.enterText(
      find.byKey(const ValueKey('table-cell-editor')),
      '72',
    );
    await key(tester, LogicalKeyboardKey.enter);
    await tester.tap(find.byKey(const ValueKey('viewer-save')));
    await tester.pump();
    expect(jsonDecode(saved.single), {
      'columns': ['level'],
      'rows': [
        {'level': 72},
      ],
    });
  });

  testWidgets('past the bounds of a table an edit is refused', (
    tester,
  ) async {
    final full = TableDataVm(
      [for (var i = 0; i < TableBounds.columns; i++) 'c$i'],
      [
        for (var r = 0; r < TableBounds.rows; r++) const <Object?>[],
      ],
    );
    await show(tester, typed(full));
    await tester.tap(find.byKey(const ValueKey('table-add-row')));
    await tester.pump();
    expect(find.text(S.current.tableRefusedRows), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('table-add-column')));
    await tester.pump();
    expect(find.text(S.current.tableRefusedColumns), findsOneWidget);
    expect(find.byKey(const ValueKey('viewer-save')), findsNothing);
  });

  testWidgets('a CSV text "As table": read by the rules, saved as CSV', (
    tester,
  ) async {
    final rules = ViewerTables(
      readCsv: (text, r) {
        final lines = text.trim().split('\n');
        final cols = lines.first.split(r.delimiter);
        return TableDataVm(cols, [
          for (final l in lines.skip(1)) l.split(r.delimiter),
        ]);
      },
      writeCsv: (t, r) => [
        t.columns.join(r.delimiter),
        for (final row in t.rows) row.join(r.delimiter),
        '',
      ].join('\n'),
    );
    const text = 'name;kw\npump;3\n';
    await show(
      tester,
      const ValueViewerVm(
        title: 'csv1.in',
        type: 'string',
        content: TextContentVm(['name;kw', 'pump;3', '']),
        copy: text,
        edit: ViewerEditVm(kind: .text, text: text),
        csv: ViewerCsvVm(delimiter: ';'),
      ),
      tables: rules,
    );
    expect(find.byKey(const ValueKey('viewer-tabs')), findsOneWidget);
    await tester.tap(find.text('As table'));
    await tester.pump();
    expect(find.textContaining('delimiter ;'), findsOneWidget);
    await tester.tap(cell(0, 1));
    await tester.pump(const Duration(milliseconds: 400));
    await key(tester, LogicalKeyboardKey.enter);
    // A CSV cell stays a text: `4` is not the number 4.
    await tester.enterText(
      find.byKey(const ValueKey('table-cell-editor')),
      '4',
    );
    await key(tester, LogicalKeyboardKey.enter);
    await tester.tap(find.byKey(const ValueKey('viewer-save')));
    await tester.pump();
    expect(saved, ['name;kw\npump;4\n']);
  });

  testWidgets('a text of several lines: the first, a mark, the viewer', (
    tester,
  ) async {
    var opened = 0;
    await tester.pumpWidget(
      frame(
        Center(
          child: SizedBox(
            width: 220,
            child: LinesText(
              'name,kw\npump,3',
              style: const TextStyle(fontSize: 12),
              onOpen: () => opened++,
            ),
          ),
        ),
      ),
    );
    expect(find.text('name,kw'), findsOneWidget);
    expect(find.text('↲ +1'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('lines-mark')));
    expect(opened, 1);
    expect(LinesText.moreLines('a'), 0);
  });

  testWidgets('a block row of several lines shows its mark', (tester) async {
    final viewed = <String>[];
    await tester.pumpWidget(
      frame(
        Center(
          child: FlowBlockView(
            vm: const FlowBlockVm(
              id: 'csv1',
              title: 'csv1',
              x: 0,
              y: 0,
              rows: [
                FieldRowVm(
                  id: 'in:in',
                  label: 'Input',
                  value: 'name,kw\npump,3\nfan,7',
                  inPort: 'in',
                ),
              ],
            ),
            actions: FlowBlockActions(
              onSelect: (_) {},
              onBind: (_, _, _) {},
              onRebind: (_, _, _, _) {},
              onUnbind: (_, _) {},
              onDropEntry: (_, _, _) {},
              onResize: (_, {required add}) {},
              onView: (b, r) => viewed.add('$b/$r'),
            ),
          ),
        ),
      ),
    );
    expect(find.text('↲ +2'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('lines-mark')));
    expect(viewed, ['csv1/in:in']);
  });

  group('table edits', () {
    test('a typed cell keeps its type', () {
      expect(typedCell('4', 3), 4);
      expect(typedCell('n/a', 3), 'n/a');
      expect(typedCell('false', true), false);
      expect(typedCell('{"a":1}', {'b': 2}), {'a': 1});
      expect(typedCell('7', 'seven'), '7');
      expect(typedCell('7', null), 7);
      expect(typedCell('', null), isNull);
      expect(typedCell('7', 3, textOnly: true), '7');
    });

    test('the cells weigh as the engine counts them', () {
      expect(
        tableBytes(
          TableDataVm(
            ['a', 'b'],
            [
              ['é', 1],
              [null],
            ],
          ),
        ),
        (2 + 3) + 9 + 1 + 1,
      );
      final heavy = TableDataVm(
        ['a'],
        [
          ['x' * (TableBounds.bytes - 10)],
          [null],
        ],
      );
      expect(setCell(heavy, 1, 0, 'y' * 20).refused, TableRefusal.bytes);
      expect(setCell(heavy, 1, 0, 'y').table, isNotNull);
    });

    test('a column name is unique and not empty', () {
      final t = TableDataVm(['a'], const []);
      expect(addColumn(t, 'a').refused, TableRefusal.nameTaken);
      expect(addColumn(t, '').refused, TableRefusal.name);
      expect(renameColumn(t, 0, 'a').table, isNotNull);
      expect(newColumnName(t), 'column_2');
    });
  });
}
