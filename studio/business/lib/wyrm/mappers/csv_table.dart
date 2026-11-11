import 'dart:convert';

import 'table_value.dart';

/// The text a `table_from_csv` reads at most (`MAX_TEXT_TABLE`, 512 KiB);
/// past it the block says `parse_error`.
const int csvMaxText = 512 * 1024;

/// A field of a CSV text the engine reads at most (`MAX_FIELD`, 64 KiB).
const int _maxField = 64 * 1024;

/// The bounds of a table (ADR 0044 §2, `crates/wyrm-flow/src/blocks/table.rs`).
const tableMaxRows = 10000;
const tableMaxColumns = 128;

/// The CSV delimiter a block's `delimiter` text gives: its first character,
/// `,` when it is empty (the engine's `chars().next().unwrap_or(',')`).
String csvDelimiter(Object? delimiter) => switch (delimiter) {
  final String s when s.isNotEmpty => String.fromCharCode(s.runes.first),
  _ => ',',
};

/// [s] read as `table_from_csv` reads it (`parse_csv` in
/// `crates/wyrm-flow/src/blocks/tables.rs`); null where the block says
/// `parse_error`.
///
/// - A quoted field is the text between its first and last quote; `""` is a
///   quote only when the field had more than two quotes.
/// - A delimiter, CR, LF or CR LF outside quotes ends a field; a line break
///   ends a row. Every line ended by a break is a row, an empty one too; the
///   last line without a break only when it has a field.
/// - With [header] the first row names the columns: an empty name is `v<n>`,
///   a name seen before gets `_2`, `_3`, …; a row longer than the header
///   adds `v<n>` columns. Without it the columns are `v1`, `v2`, ….
/// - Every cell is a text; a row shorter than the columns lacks the rest
///   (null).
/// - Refused while it reads: a text past [csvMaxText], a row of more than
///   [tableMaxColumns] fields, a field past 64 KiB, more than
///   [tableMaxRows] + 1 lines; no row at all.
TableValue? parseCsv(String s, {String delimiter = ',', bool header = true}) {
  if (utf8.encode(s).length > csvMaxText) {
    return null;
  }
  final delim = csvDelimiter(delimiter);
  final rows = <List<String>>[];
  var row = <String>[];
  final raw = StringBuffer();
  var rawBytes = 0;
  var quotes = 0;
  int? firstQ;
  int? lastQ;

  void endField() {
    final text = raw.toString();
    final String f;
    if (quotes > 0 && firstQ != null && lastQ != null && lastQ! > firstQ!) {
      final inner = text.substring(firstQ! + 1, lastQ);
      f = quotes > 2 ? inner.replaceAll('""', '"') : inner;
    } else if (quotes > 0 && firstQ != null) {
      f = text.substring(firstQ! + 1);
    } else {
      f = text;
    }
    raw.clear();
    rawBytes = 0;
    quotes = 0;
    firstQ = null;
    lastQ = null;
    row.add(f);
  }

  final chars = s.runes.toList();
  for (var i = 0; i < chars.length; i++) {
    if (row.length > tableMaxColumns || rawBytes > _maxField) {
      return null;
    }
    final c = String.fromCharCode(chars[i]);
    if (c == '"') {
      final at = raw.length;
      firstQ ??= at;
      lastQ = at;
      quotes++;
      raw.write(c);
      rawBytes++;
      continue;
    }
    if (quotes.isEven && (c == delim || c == '\n' || c == '\r')) {
      endField();
      if (c != delim) {
        if (c == '\r' && i + 1 < chars.length && chars[i + 1] == 0x0a) {
          i++;
        }
        rows.add(row);
        row = [];
        if (rows.length > tableMaxRows + 1) {
          return null;
        }
      }
      continue;
    }
    raw.write(c);
    rawBytes += utf8.encode(c).length;
  }
  if (row.length > tableMaxColumns || rawBytes > _maxField) {
    return null;
  }
  if (raw.isNotEmpty || quotes > 0 || row.isNotEmpty) {
    endField();
    if (row.length > 1 || row.first.isNotEmpty) {
      rows.add(row);
    }
  }
  if (rows.isEmpty) {
    return null;
  }
  var width = 0;
  for (final r in rows) {
    if (r.length > width) {
      width = r.length;
    }
  }
  if (width > tableMaxColumns) {
    return null;
  }
  final List<String> columns;
  final Iterable<List<String>> body;
  if (header) {
    final names = _Names();
    for (final (i, n) in rows.first.indexed) {
      names.add(n.isEmpty ? 'v${i + 1}' : n);
    }
    while (names.list.length < width) {
      names.add('v${names.list.length + 1}');
    }
    columns = names.list;
    body = rows.skip(1);
  } else {
    columns = [for (var i = 1; i <= width; i++) 'v$i'];
    body = rows;
  }
  return TableValue(columns, [
    for (final r in body)
      [for (var i = 0; i < columns.length; i++) i < r.length ? r[i] : null],
  ]);
}

/// Column names made unique in one pass, as the engine's `Names`.
final class _Names {
  final list = <String>[];
  final _seen = <String>{};
  final _next = <String, int>{};

  void add(String base) {
    var n = base;
    if (_seen.contains(n)) {
      var k = _next[base] ?? 2;
      do {
        n = '${base}_$k';
        k++;
      } while (_seen.contains(n));
      _next[base] = k;
    }
    _seen.add(n);
    list.add(n);
  }
}

/// [columns] and [rows] (cells by position) as CSV, as `table_to_csv`
/// writes it (`write_csv`): a field with a quote is quoted with its quotes
/// doubled, one with the delimiter or a line break is quoted; every row ends
/// with a line break; a cell as the engine's text (null empty, a list or a
/// map as JSON).
String writeCsv(
  List<String> columns,
  List<List<Object?>> rows, {
  String delimiter = ',',
  bool header = true,
}) {
  final d = csvDelimiter(delimiter);
  String q(String x) {
    if (x.contains('"')) {
      return '"${x.replaceAll('"', '""')}"';
    }
    if (x.contains(d) || x.contains('\n') || x.contains('\r')) {
      return '"$x"';
    }
    return x;
  }

  final out = StringBuffer();
  if (header) {
    out
      ..writeAll(columns.map(q), d)
      ..write('\n');
  }
  for (final r in rows) {
    out
      ..writeAll([
        for (var i = 0; i < columns.length; i++)
          q(cellText(i < r.length ? r[i] : null)),
      ], d)
      ..write('\n');
  }
  return out.toString();
}

/// A cell as the engine writes it in a text (`text` in `blocks.rs`): null
/// empty, a text itself, a number and a bool as written, a list or a map as
/// compact JSON.
String cellText(Object? v) => switch (v) {
  null => '',
  final String s => s,
  final bool b => '$b',
  final int i => '$i',
  final double x => '$x',
  _ => _json(v),
};

String _json(Object? v) => jsonEncode(_plain(v));

/// [v] as JSON can hold it: keys as texts, a number that is not finite and
/// anything else JSON lacks as its text.
Object? _plain(Object? v) => switch (v) {
  final double d when !d.isFinite => '$d',
  null || bool() || num() || String() => v,
  final Map<Object?, Object?> m => {
    for (final e in m.entries) '${e.key}': _plain(e.value),
  },
  final List<Object?> l => [for (final x in l) _plain(x)],
  _ => '$v',
};
