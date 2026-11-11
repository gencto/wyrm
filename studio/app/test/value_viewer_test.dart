import 'dart:typed_data';

import 'package:app/common/value_viewer.dart';
import 'package:business/wyrm/mappers/flow_canvas.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:ui/overlays/value_viewer.dart';
import 'package:ui/tables/table_edits.dart';
import 'package:ui/trees/json_tree.dart';

void main() {
  setUpAll(() => S.load(const Locale('en')));

  test('a map is a tree, copied as indented JSON', () {
    final v = valueViewerOf(
      title: 'show.in',
      value: {
        'tank': 'tank 3',
        'level': 72.4,
        'limits': {'low': 20},
        'pumps': [1, null, true],
      },
    );
    expect(v.type, 'map');
    expect(v.size, '4 keys');
    final root = (v.content as JsonContentVm).root;
    expect(root.kind, JsonKind.object);
    expect(
      [for (final c in root.children) c.key],
      [
        'tank',
        'level',
        'limits',
        'pumps',
      ],
    );
    expect(root.children.first.text, '"tank 3"');
    expect(root.children[3].children.map((c) => c.kind), [
      JsonKind.number,
      JsonKind.nil,
      JsonKind.flag,
    ]);
    expect(v.copy, contains('\n  "tank": "tank 3"'));
  });

  test('a table is all its rows, one grid per value, copied as JSON', () {
    final value = {
      'columns': ['name', 'kw'],
      'rows': [
        for (var i = 0; i < 10000; i++) {'name': 'p$i', 'kw': i},
      ],
    };
    final v = valueViewerOf(title: 'sort.out', value: value);
    expect(v.type, 'table');
    expect(v.size, '10000 rows · 2 columns');
    final t = (v.content as TableContentVm).table;
    expect(t.columns, ['name', 'kw']);
    expect(t.rows, hasLength(10000));
    expect(t.rows.first, ['p0', 0]);
    expect(t.rows.last, ['p9999', 9999]);
    expect(v.copy, contains('"columns"'));
    // Built again for the same value (a dispatch), it is the same grid:
    // the view-model compares equal at once.
    final again = valueViewerOf(title: 'sort.out', value: value);
    expect(identical((again.content as TableContentVm).table, t), isTrue);
    expect(again, v);
  });

  test('a typed table with no columns is still a grid to edit', () {
    final empty = {'columns': <String>[], 'rows': <Object?>[]};
    expect(
      valueViewerOf(title: 't.value', value: empty).content,
      isA<EmptyContentVm>(),
    );
    final v = valueViewerOf(title: 't.value', value: empty, editable: true);
    expect((v.content as TableContentVm).table.columns, isEmpty);
  });

  test('the viewers read a CSV by the block rules, dates by the column', () {
    final t = viewerTables.readCsv!(
      'name;kw\npump;3\n',
      const ViewerCsvVm(delimiter: ';'),
    )!;
    expect(t.columns, ['name', 'kw']);
    expect(t.rows, [
      ['pump', '3'],
    ]);
    expect(
      viewerTables.writeCsv!(t, const ViewerCsvVm(delimiter: ';')),
      'name;kw\npump;3\n',
    );
    expect(
      viewerTables.readCsv!('', const ViewerCsvVm()),
      isNull,
      reason: 'the block says parse_error',
    );
    expect(viewerTables.copyCsv!(t), 'name,kw\npump,3\n');
    final us = DateTime.utc(2026, 11, 11).microsecondsSinceEpoch;
    expect(viewerTables.cellText!('t', us), isNotNull);
    expect(viewerTables.cellText!('kw', 3), isNull);
  });

  test('a list of maps is a table where a table is expected only', () {
    final rows = [
      {'name': 'pump', 'kw': 3},
      {'name': 'fan', 'zone': 'A'},
    ];
    final t = valueViewerOf(title: 'h.out', value: rows, rowsOfMaps: true);
    expect(t.type, 'table');
    expect((t.content as TableContentVm).table.columns, [
      'name',
      'kw',
      'zone',
    ]);
    // Elsewhere (the Explorer) a list stays a tree.
    expect(valueViewerOf(title: 'p', value: rows).type, 'list');
  });

  test('a date of the engine reads as a date, with UTC and the number', () {
    final us = DateTime.utc(2026, 11, 11, 10, 29, 3).microsecondsSinceEpoch;
    final v = valueViewerOf(title: 'now.out', value: us, date: true);
    expect(v.type, 'date');
    final n = v.content as NumberContentVm;
    expect(n.unit, '2026-11-11T10:29:03Z · $us µs');
    expect(v.copy, '$us');
    expect(valueViewerOf(title: 'x', value: us).type, 'number');
  });

  test('a list of ints stays a list, not bytes', () {
    final v = valueViewerOf(title: 'x', value: [1, 2, 3]);
    expect(v.type, 'list');
    expect(v.size, '3 items');
    expect(v.content, isA<JsonContentVm>());
  });

  test('a text is numbered lines; a JSON text is a tree', () {
    final t = valueViewerOf(title: 'text.out', value: 'one\ntwo');
    expect(t.type, 'string');
    expect(t.size, '7 chars · 2 lines');
    expect((t.content as TextContentVm).lines, ['one', 'two']);
    expect(t.copy, 'one\ntwo');

    final j = valueViewerOf(title: 'q.out', value: '{"a": 1}');
    expect(j.type, 'string · JSON');
    expect(j.content, isA<JsonContentVm>());
    expect(j.copy, '{"a": 1}');

    expect(
      valueViewerOf(title: 'q', value: '{oops').content,
      isA<TextContentVm>(),
    );
  });

  test('a number has its unit; an enum its name', () {
    final n = valueViewerOf(title: 'level', value: 72.4, unit: '%');
    expect(n.content, const NumberContentVm('72.4', unit: '%'));
    expect(n.copy, '72.4');

    final e = valueViewerOf(title: 'mode', value: 1, choices: ['off', 'on']);
    expect(e.type, 'enum');
    expect(e.content, const NumberContentVm('on', unit: '= 1'));
  });

  test('a bool is a mark and its word', () {
    final b = valueViewerOf(title: 'armed', value: true);
    expect(b.content, const FlagContentVm(value: true, word: 'true'));
  });

  test('bytes are a hex dump', () {
    final b = valueViewerOf(
      title: 'raw',
      value: Uint8List.fromList('Hello, WYRM!\x00\x01'.codeUnits),
    );
    expect(b.type, 'bytes');
    expect(b.size, '14 bytes');
    final rows = (b.content as BytesContentVm).rows;
    expect(rows, hasLength(1));
    expect(rows.single, startsWith('00000000  48 65 6c 6c 6f'));
    expect(rows.single, endsWith('Hello, WYRM!..'));
    expect(b.copy, startsWith('48656c6c6f'));
  });

  test('no sample yet, and null', () {
    expect(
      valueViewerOf(title: 'x', value: null, known: false).content,
      const EmptyContentVm('no value'),
    );
    expect(
      valueViewerOf(title: 'x', value: null).content,
      const EmptyContentVm('null'),
    );
  });

  test('a map JSON cannot hold is copied as Dart writes it', () {
    final v = valueViewerOf(title: 'x', value: {1: 'a'});
    expect(v.copy, '{1: a}');
  });

  test('a table saved from its grid is the value the field takes', () {
    // The grid's Save hands the viewer's onSave this text; the editor's
    // `_setField` reads it as the inspector does (FieldEdit.json).
    final grid = TableDataVm(
      ['name', 'kw'],
      [
        ['pump', 4.5],
        ['fan'],
      ],
    );
    final value = typedText(grid.toJsonText(), FieldEdit.json);
    expect(value, {
      'columns': ['name', 'kw'],
      'rows': [
        {'name': 'pump', 'kw': 4.5},
        {'name': 'fan', 'kw': null},
      ],
    });
    // Read back, it is the same table.
    final again = tableDataOf(value)!;
    expect(again.columns, grid.columns);
    expect(again.rows, [
      ['pump', 4.5],
      ['fan', null],
    ]);
  });
}
