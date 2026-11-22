import 'dart:convert';
import 'dart:typed_data';

/// A cell of a table as the grid holds it, by what it holds. [raw] is the
/// value as it came (what Save writes back); [json] the value as JSON can
/// hold it.
sealed class CellVm {
  const CellVm();

  /// The value as it came.
  Object? get raw;

  /// The value as JSON can hold it: map keys as texts, a number that is
  /// not finite as its text, bytes as base64, anything else as its text.
  Object? get json;
}

/// An empty cell: `null`.
final class NullCell extends CellVm {
  const NullCell();

  @override
  Object? get raw => null;

  @override
  Object? get json => null;
}

/// A bool.
final class FlagCell extends CellVm {
  const FlagCell(this.value);

  final bool value;

  @override
  Object? get raw => value;

  @override
  Object? get json => value;
}

/// A number.
final class NumberCell extends CellVm {
  const NumberCell(this.value);

  final num value;

  @override
  Object? get raw => value;

  @override
  Object? get json => value.isFinite ? value : '$value';
}

/// A text.
final class TextCell extends CellVm {
  const TextCell(this.text);

  final String text;

  @override
  Object? get raw => text;

  @override
  Object? get json => text;
}

/// Bytes.
final class BytesCell extends CellVm {
  const BytesCell(this.bytes);

  final Uint8List bytes;

  @override
  Object? get raw => bytes;

  @override
  Object? get json => base64Encode(bytes);
}

/// A list: its [items] in order.
final class ListCell extends CellVm {
  const ListCell(this.items, {required this.raw});

  final List<CellVm> items;

  @override
  final Object raw;

  @override
  Object? get json => [for (final x in items) x.json];
}

/// A map: its [entries] in order.
final class MapCell extends CellVm {
  const MapCell(this.entries, {required this.raw});

  final List<CellEntryVm> entries;

  @override
  final Object raw;

  @override
  Object? get json => {for (final e in entries) e.key: e.value.json};
}

/// One field of a [MapCell]: its key as text.
final class CellEntryVm {
  const CellEntryVm(this.key, this.value);

  final String key;
  final CellVm value;
}

/// Anything else: its [text] as Dart writes it.
final class OtherCell extends CellVm {
  const OtherCell(this.text, {required this.raw});

  final String text;

  @override
  final Object raw;

  @override
  Object? get json => text;
}

/// A table as a grid holds it (ADR 0044 §2): its [columns] in order and its
/// [rows], each one cell per column by position ([NullCell] where a row
/// lacks one).
///
/// It compares by identity on purpose: a table may hold 10 000 rows, and a
/// view-model that holds it is compared on every dispatch. The app keeps
/// one instance per value it shows, so the same value is the same instance.
final class TableDataVm {
  TableDataVm(this.columns, this.rows);

  /// No columns, no rows: what a new table variable starts with.
  TableDataVm.empty() : columns = const [], rows = const [];

  final List<String> columns;
  final List<List<CellVm>> rows;

  /// The cell of row [r], column [c]; [NullCell] past the row's end.
  CellVm cell(int r, int c) {
    final row = rows[r];
    return c < row.length ? row[c] : const NullCell();
  }

  /// As the engine writes a table: `{columns, rows}`, each row a map of
  /// every column (a cell it lacks is `null`), as `Table::to_value` does.
  Map<String, Object?> toJson() => {
    'columns': columns,
    'rows': [
      for (var r = 0; r < rows.length; r++)
        {for (final (c, name) in columns.indexed) name: cell(r, c).raw},
    ],
  };

  /// [toJson] as indented JSON (each cell as [CellVm.json]): what Save
  /// writes into the field.
  String toJsonText() => const JsonEncoder.withIndent('  ').convert({
    'columns': columns,
    'rows': [
      for (var r = 0; r < rows.length; r++)
        {for (final (c, name) in columns.indexed) name: cell(r, c).json},
    ],
  });
}

/// The bounds of a table (ADR 0044 §2, `crates/wyrm-flow/src/blocks/table.rs`).
abstract final class TableBounds {
  static const rows = 10000;
  static const columns = 128;

  /// A column name, in UTF-8 bytes.
  static const name = 256;

  /// The cells, counted as the engine's `size` counts them.
  static const int bytes = 512 * 1024;
}

/// Why an edit of a table is refused.
enum TableRefusal {
  /// It would hold more than [TableBounds.rows] rows.
  rows,

  /// It would hold more than [TableBounds.columns] columns.
  columns,

  /// Its cells would weigh more than [TableBounds.bytes].
  bytes,

  /// A column name that is empty or longer than [TableBounds.name] bytes.
  name,

  /// A column name the table already has.
  nameTaken,
}

/// What an edit gives: the new table, or why it is refused.
typedef TableEdit = ({TableDataVm? table, TableRefusal? refused});

TableEdit _ok(TableDataVm t) => (table: t, refused: null);
TableEdit _no(TableRefusal why) => (table: null, refused: why);

/// The weight of the cells of [t] as the engine counts it (`size` in
/// `table.rs`): null and a bool 1, a number 9, a text its UTF-8 bytes + 3,
/// a list its items + 3, a map its keys' bytes + 3 each and its values + 3.
/// Every column of every row counts (a cell a row lacks is a `null`).
int tableBytes(TableDataVm t) {
  var n = 0;
  for (final r in t.rows) {
    for (var c = 0; c < t.columns.length; c++) {
      n += c < r.length ? cellBytes(r[c]) : 1;
    }
  }
  return n;
}

/// The weight of one cell, as [tableBytes] counts it.
int cellBytes(CellVm v) => switch (v) {
  NullCell() || FlagCell() => 1,
  NumberCell() => 9,
  TextCell(:final text) => utf8Length(text) + 3,
  BytesCell(:final bytes) => bytes.length + 3,
  ListCell(:final items) => items.fold<int>(3, (n, x) => n + cellBytes(x)),
  MapCell(:final entries) => entries.fold<int>(
    3,
    (n, e) => n + utf8Length(e.key) + 3 + cellBytes(e.value),
  ),
  OtherCell(:final text) => utf8Length(text) + 3,
};

/// The UTF-8 length of [s], without encoding it.
int utf8Length(String s) {
  var n = 0;
  for (var i = 0; i < s.length; i++) {
    final u = s.codeUnitAt(i);
    if (u < 0x80) {
      n += 1;
    } else if (u < 0x800) {
      n += 2;
    } else if (u >= 0xd800 && u <= 0xdbff && i + 1 < s.length) {
      n += 4;
      i++;
    } else {
      n += 3;
    }
  }
  return n;
}

List<List<CellVm>> _copyRows(TableDataVm t) => [
  for (final r in t.rows) List<CellVm>.of(r),
];

/// [t] with cell [r], [c] set to [v]; refused past [TableBounds.bytes].
TableEdit setCell(TableDataVm t, int r, int c, CellVm v) {
  final was = t.cell(r, c);
  if (cellBytes(v) > cellBytes(was) &&
      tableBytes(t) - cellBytes(was) + cellBytes(v) > TableBounds.bytes) {
    return _no(.bytes);
  }
  final rows = List<List<CellVm>>.of(t.rows);
  final row = List<CellVm>.of(rows[r]);
  while (row.length < t.columns.length) {
    row.add(const NullCell());
  }
  row[c] = v;
  rows[r] = row;
  return _ok(TableDataVm(t.columns, rows));
}

/// [t] with an empty row (every cell `null`) at [at] (the end when null).
TableEdit addRow(TableDataVm t, {int? at}) {
  if (t.rows.length >= TableBounds.rows) {
    return _no(.rows);
  }
  if (tableBytes(t) + t.columns.length > TableBounds.bytes) {
    return _no(.bytes);
  }
  final rows = List<List<CellVm>>.of(t.rows)
    ..insert(
      (at ?? t.rows.length).clamp(0, t.rows.length),
      List<CellVm>.filled(t.columns.length, const NullCell()),
    );
  return _ok(TableDataVm(t.columns, rows));
}

/// [t] without row [r].
TableEdit removeRow(TableDataVm t, int r) =>
    _ok(TableDataVm(t.columns, List<List<CellVm>>.of(t.rows)..removeAt(r)));

/// Why [name] cannot name a column of [t] (other than column [except]);
/// null when it can.
TableRefusal? nameRefusal(TableDataVm t, String name, {int? except}) {
  if (name.isEmpty || utf8Length(name) > TableBounds.name) {
    return .name;
  }
  for (final (i, n) in t.columns.indexed) {
    if (i != except && n == name) {
      return .nameTaken;
    }
  }
  return null;
}

/// A name for a new column of [t]: `column_<n>`, the first one it lacks.
String newColumnName(TableDataVm t) {
  for (var i = t.columns.length + 1; ; i++) {
    final n = 'column_$i';
    if (!t.columns.contains(n)) {
      return n;
    }
  }
}

/// [t] with a column [name] (its cells `null`) at [at] (the end when null).
TableEdit addColumn(TableDataVm t, String name, {int? at}) {
  if (t.columns.length >= TableBounds.columns) {
    return _no(.columns);
  }
  if (nameRefusal(t, name) case final why?) {
    return _no(why);
  }
  if (tableBytes(t) + t.rows.length > TableBounds.bytes) {
    return _no(.bytes);
  }
  final i = (at ?? t.columns.length).clamp(0, t.columns.length);
  final rows = _copyRows(t);
  for (final r in rows) {
    while (r.length < t.columns.length) {
      r.add(const NullCell());
    }
    r.insert(i, const NullCell());
  }
  return _ok(TableDataVm(List.of(t.columns)..insert(i, name), rows));
}

/// [t] with column [c] named [name].
TableEdit renameColumn(TableDataVm t, int c, String name) {
  if (nameRefusal(t, name, except: c) case final why?) {
    return _no(why);
  }
  return _ok(TableDataVm(List.of(t.columns)..[c] = name, t.rows));
}

/// [t] without column [c].
TableEdit removeColumn(TableDataVm t, int c) {
  final rows = _copyRows(t);
  for (final r in rows) {
    if (c < r.length) {
      r.removeAt(c);
    }
  }
  return _ok(TableDataVm(List.of(t.columns)..removeAt(c), rows));
}

/// A JSON text read as a cell: a map, a list or a scalar; null when the
/// text is no JSON. The app gives it (`ViewerTables.readJson`): a value
/// is decoded at its boundary, not in a widget.
typedef CellJsonOf = CellVm? Function(String text);

/// What a cell typed as [text] holds, by what it held before ([was]): a
/// number stays a number when the text reads as one, a bool a bool for
/// `true`/`false`, a map or a list one when the text is its JSON (read by
/// [readJson]; none: the text); anything else is the text. An empty cell
/// takes a number or a bool when the text is one, else the text; an empty
/// text leaves it empty. With [textOnly] (a CSV cell) the text is kept as
/// it is.
CellVm typedCell(
  String text,
  CellVm was, {
  bool textOnly = false,
  CellJsonOf? readJson,
}) {
  if (textOnly) {
    return TextCell(text);
  }
  final s = text.trim();
  NumberCell? asNumber() => switch (num.tryParse(s)) {
    final n? when n.isFinite => NumberCell(n),
    _ => null,
  };
  FlagCell? asFlag() => s == 'true'
      ? const FlagCell(true)
      : (s == 'false' ? const FlagCell(false) : null);
  return switch (was) {
    NumberCell() =>
      s.isEmpty ? const NullCell() : (asNumber() ?? TextCell(text)),
    FlagCell() => s.isEmpty ? const NullCell() : (asFlag() ?? TextCell(text)),
    // bytes are read as a list (a list of numbers in JSON)
    MapCell() || ListCell() || BytesCell() =>
      s.isEmpty
          ? const NullCell()
          : switch (readJson?.call(s)) {
              final MapCell m => m,
              final ListCell l => l,
              _ => TextCell(text),
            },
    NullCell() =>
      s.isEmpty ? const NullCell() : (asNumber() ?? asFlag() ?? TextCell(text)),
    TextCell() || OtherCell() => TextCell(text),
  };
}

/// A cell as its editor starts with it: a text itself, a number or a bool
/// as written, a map, a list or bytes as compact JSON, `null` empty.
String cellEditText(CellVm v) => switch (v) {
  NullCell() => '',
  TextCell(:final text) => text,
  MapCell() || ListCell() || BytesCell() => jsonEncode(v.json),
  FlagCell(:final value) => '$value',
  NumberCell(:final value) => '$value',
  OtherCell(:final text) => text,
};
