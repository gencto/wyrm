import 'package:models/plain_value.dart';

import 'plain_value.dart';

/// A table of the flow engine (ADR 0044 §2) read for showing: its columns
/// in order and its rows as cells by column, [PlainValueNothing] where a
/// row lacks one.
final class TableValue {
  const TableValue(this.columns, this.rows);

  final List<String> columns;

  /// Every row, each with one cell per column.
  final List<List<PlainValue>> rows;
}

/// [v] (a value as a sample holds it) as a table, or null when it is none.
///
/// - `{columns: [...], rows: [...]}`, as `Table::to_value` writes it
///   (`crates/wyrm-flow/src/blocks/table.rs`: `columns` an array of texts,
///   each row a map of every column; a row may also be a list, cells by
///   position, as `Table::from_value` takes it);
/// - with [rowsOfMaps], also a list of maps (the rows of `list_children`,
///   `load_history`, a `split`): its columns are the keys in the order they
///   first appear. Without it a list stays a list: a value elsewhere (the
///   Explorer) is not read as a table by its shape alone.
///
/// Read once per value: the same map or list gives the same [TableValue].
TableValue? tableValueOf(Object? v, {bool rowsOfMaps = false}) {
  if (v is! Map<Object?, Object?> && v is! List<Object?>) {
    return null;
  }
  final cache = rowsOfMaps ? _ofMaps : _tables;
  return (cache[v!] ??= (_read(v, rowsOfMaps: rowsOfMaps),)).$1;
}

final _tables = Expando<(TableValue?,)>('tables');
final _ofMaps = Expando<(TableValue?,)>('tables of maps');

TableValue? _read(Object v, {required bool rowsOfMaps}) {
  switch (v) {
    case {'columns': final List<Object?> cols, 'rows': final List<Object?> rs}
        when v.length == 2 && cols.every((c) => c is String):
      final columns = [for (final c in cols) '$c'];
      final rows = <List<PlainValue>>[];
      for (final r in rs) {
        switch (r) {
          case final Map<Object?, Object?> m:
            rows.add([for (final c in columns) plainValueOf(m[c])]);
          case final List<Object?> l:
            rows.add([
              for (var i = 0; i < columns.length; i++)
                plainValueOf(i < l.length ? l[i] : null),
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
      final maps = [
        for (final r in l)
          if (r case final Map<Object?, Object?> m) m,
      ];
      final columns = <String>[];
      for (final r in maps) {
        for (final k in r.keys) {
          if (!columns.contains('$k')) {
            columns.add('$k');
          }
        }
      }
      return TableValue(columns, [
        for (final r in maps) [for (final c in columns) plainValueOf(r[c])],
      ]);
    default:
      return null;
  }
}
