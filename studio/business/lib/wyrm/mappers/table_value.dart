import 'value_text.dart';

/// A table of the flow engine (ADR 0044 §2) read for showing: its columns
/// in order and its rows as cells by column, `null` where a row lacks one.
final class TableValue {
  const TableValue(this.columns, this.rows);

  final List<String> columns;

  /// Every row, each with one cell per column.
  final List<List<Object?>> rows;

  /// The first [max] rows as texts: a cell as [valueText] writes it, a date
  /// of the time column `t` (µs, as `load_history` and `table_recorder`
  /// give it) as [dateText].
  List<List<String>> texts({int max = 200}) => [
    for (final r in rows.take(max))
      [
        for (final (i, c) in r.indexed)
          switch (c) {
            null => '',
            final num n when columns[i] == 't' && dateText(n) != null =>
              dateText(n)!,
            final String s => s,
            _ => valueText(c),
          },
      ],
  ];
}

/// [v] as a table, or null when it is none.
///
/// - `{columns: [...], rows: [...]}`: a row is a map (cells by name) or a
///   list (cells by position);
/// - with [rowsOfMaps], also a list of maps (the rows of `list_children`,
///   `load_history`, a `split`): its columns are the keys in the order they
///   first appear. Without it a list stays a list: a value elsewhere (the
///   Explorer) is not read as a table by its shape alone.
TableValue? tableOf(Object? v, {bool rowsOfMaps = false}) {
  switch (v) {
    case {'columns': final List<Object?> cols, 'rows': final List<Object?> rs}
        when v.length == 2 && cols.every((c) => c is String):
      final columns = cols.cast<String>();
      final rows = <List<Object?>>[];
      for (final r in rs) {
        switch (r) {
          case final Map<Object?, Object?> m:
            rows.add([for (final c in columns) m[c]]);
          case final List<Object?> l:
            rows.add([
              for (var i = 0; i < columns.length; i++)
                i < l.length ? l[i] : null,
            ]);
          default:
            return null;
        }
      }
      return TableValue(columns, rows);
    case final List<Object?> l
        when rowsOfMaps &&
            l.isNotEmpty &&
            l.every((r) => r is Map<Object?, Object?>):
      final columns = <String>[];
      for (final r in l.cast<Map<Object?, Object?>>()) {
        for (final k in r.keys) {
          if (!columns.contains('$k')) {
            columns.add('$k');
          }
        }
      }
      return TableValue(columns, [
        for (final r in l.cast<Map<Object?, Object?>>())
          [for (final c in columns) r[c]],
      ]);
    default:
      return null;
  }
}
