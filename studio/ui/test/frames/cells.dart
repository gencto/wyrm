import 'dart:convert';
import 'dart:typed_data';

import 'package:ui/tables/table_edits.dart';

/// Test data as the app hands a grid its cells: [v] (plain Dart) as the
/// [CellVm] it is. The app reads a sample through its decoder; a test
/// writes its tables as plain lists.
CellVm cellOf(Object? v) => switch (v) {
  null => const NullCell(),
  final bool b => FlagCell(b),
  final num n => NumberCell(n),
  final String s => TextCell(s),
  final Uint8List b => BytesCell(b),
  final Map<Object?, Object?> m => MapCell([
    for (final e in m.entries) CellEntryVm('${e.key}', cellOf(e.value)),
  ], raw: m),
  final List<Object?> l => ListCell([for (final x in l) cellOf(x)], raw: l),
  final Object o => OtherCell('$o', raw: o),
};

/// A table of [columns] and plain [rows].
TableDataVm rawTable(List<String> columns, List<List<Object?>> rows) =>
    TableDataVm(columns, [
      for (final r in rows) [for (final x in r) cellOf(x)],
    ]);

/// [table]'s cells as plain Dart, to compare.
List<List<Object?>> rawRows(TableDataVm table) => [
  for (final r in table.rows) [for (final c in r) c.raw],
];

/// A JSON text as a cell, as the app reads one; null when it is no JSON.
CellVm? readJsonCell(String text) {
  try {
    return cellOf(jsonDecode(text));
  } on FormatException {
    return null;
  }
}
