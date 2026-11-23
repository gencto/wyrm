import 'value_text.dart';

/// A cell's own text in a table viewer: a date of the time column `t`
/// (µs, as `load_history` and `table_recorder` give it) as [dateText];
/// null for any other cell (the grid writes it by its type). [cell] is the
/// cell's number; null for a cell that is none.
String? tableCellText(String column, num? cell) =>
    column == 't' && cell != null ? dateText(cell) : null;
