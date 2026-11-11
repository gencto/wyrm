import 'dart:convert';
import 'dart:typed_data';

/// A table as a grid holds it (ADR 0044 §2): its [columns] in order and its
/// [rows], each one cell per column by position (`null` where a row lacks
/// one).
///
/// It compares by identity on purpose: a table may hold 10 000 rows, and a
/// view-model that holds it is compared on every dispatch. The app keeps
/// one instance per value it shows, so the same value is the same instance.
final class TableDataVm {
  TableDataVm(this.columns, this.rows);

  /// No columns, no rows: what a new table variable starts with.
  TableDataVm.empty() : columns = const [], rows = const [];

  final List<String> columns;
  final List<List<Object?>> rows;

  /// The cell of row [r], column [c]; null past the row's end.
  Object? cell(int r, int c) {
    final row = rows[r];
    return c < row.length ? row[c] : null;
  }

  /// As the engine writes a table: `{columns, rows}`, each row a map of
  /// every column (a cell it lacks is `null`), as `Table::to_value` does.
  Map<String, Object?> toJson() => {
    'columns': columns,
    'rows': [
      for (var r = 0; r < rows.length; r++)
        {for (final (c, name) in columns.indexed) name: cell(r, c)},
    ],
  };

  /// [toJson] as indented JSON: what Save writes into the field.
  String toJsonText() =>
      const JsonEncoder.withIndent('  ').convert(jsonSafe(toJson()));
}

/// [v] as JSON can hold it: map keys as texts, a number that is not
/// finite as its text, bytes as base64, anything else as its text.
Object? jsonSafe(Object? v) => switch (v) {
  final double d when !d.isFinite => '$d',
  null || bool() || num() || String() => v,
  final Uint8List b => base64Encode(b),
  final Map<Object?, Object?> m => {
    for (final e in m.entries) '${e.key}': jsonSafe(e.value),
  },
  final List<Object?> l => [for (final x in l) jsonSafe(x)],
  _ => '$v',
};

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
      n += cellBytes(c < r.length ? r[c] : null);
    }
  }
  return n;
}

/// The weight of one cell, as [tableBytes] counts it.
int cellBytes(Object? v) => switch (v) {
  null || bool() => 1,
  num() => 9,
  final String s => utf8Length(s) + 3,
  final Uint8List b => b.length + 3,
  final List<Object?> l => l.fold<int>(3, (n, x) => n + cellBytes(x)),
  final Map<Object?, Object?> m => m.entries.fold<int>(
    3,
    (n, e) => n + utf8Length('${e.key}') + 3 + cellBytes(e.value),
  ),
  _ => utf8Length('$v') + 3,
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

List<List<Object?>> _copyRows(TableDataVm t) => [
  for (final r in t.rows) List<Object?>.of(r),
];

/// [t] with cell [r], [c] set to [v]; refused past [TableBounds.bytes].
TableEdit setCell(TableDataVm t, int r, int c, Object? v) {
  final was = t.cell(r, c);
  if (cellBytes(v) > cellBytes(was) &&
      tableBytes(t) - cellBytes(was) + cellBytes(v) > TableBounds.bytes) {
    return _no(.bytes);
  }
  final rows = List<List<Object?>>.of(t.rows);
  final row = List<Object?>.of(rows[r]);
  while (row.length < t.columns.length) {
    row.add(null);
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
  final rows = List<List<Object?>>.of(t.rows)
    ..insert(
      (at ?? t.rows.length).clamp(0, t.rows.length),
      List<Object?>.filled(t.columns.length, null),
    );
  return _ok(TableDataVm(t.columns, rows));
}

/// [t] without row [r].
TableEdit removeRow(TableDataVm t, int r) =>
    _ok(TableDataVm(t.columns, List<List<Object?>>.of(t.rows)..removeAt(r)));

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
      r.add(null);
    }
    r.insert(i, null);
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

/// What a cell typed as [text] holds, by what it held before ([was]): a
/// number stays a number when the text reads as one, a bool a bool for
/// `true`/`false`, a map or a list one when the text is its JSON; anything
/// else is the text. An empty cell (`null`) takes a number or a bool when
/// the text is one, else the text; an empty text leaves it `null`. With
/// [textOnly] (a CSV cell) the text is kept as it is.
Object? typedCell(String text, Object? was, {bool textOnly = false}) {
  if (textOnly) {
    return text;
  }
  final s = text.trim();
  num? number() => switch (num.tryParse(s)) {
    final n? when n.isFinite => n,
    _ => null,
  };
  bool? flag() => s == 'true' ? true : (s == 'false' ? false : null);
  switch (was) {
    case num():
      return s.isEmpty ? null : (number() ?? text);
    case bool():
      return s.isEmpty ? null : (flag() ?? text);
    case Map<Object?, Object?>() || List<Object?>():
      if (s.isEmpty) {
        return null;
      }
      try {
        return switch (jsonDecode(s)) {
          final Map<Object?, Object?> m => m,
          final List<Object?> l => l,
          _ => text,
        };
      } on FormatException {
        return text;
      }
    case null:
      return s.isEmpty ? null : (number() ?? flag() ?? text);
    default:
      return text;
  }
}

/// A cell as its editor starts with it: a text itself, a number or a bool
/// as written, a map or a list as compact JSON, `null` empty.
String cellEditText(Object? v) => switch (v) {
  null => '',
  final String s => s,
  Map<Object?, Object?>() || List<Object?>() => jsonEncode(jsonSafe(v)),
  _ => '$v',
};
