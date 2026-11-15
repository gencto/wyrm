import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'action_answer.freezed.dart';

/// The answer of one run of a node's action, as Explorer shows it under the
/// action cards: a table when the rows are records, else the rows as JSON
/// lines.
@freezed
abstract class ActionAnswer with _$ActionAnswer {
  const factory ActionAnswer({
    /// The records' fields, in the order first seen (at most six).
    @Default(IListConst([])) IList<String> columns,

    /// One cell per column, as text; empty when the answer is no table.
    @Default(IListConst([])) IList<IList<String>> rows,

    /// How many rows the action answered.
    @Default(0) int count,

    /// Each row as indented JSON, split into lines.
    @Default(IListConst([])) IList<String> lines,
  }) = _ActionAnswer;
}
