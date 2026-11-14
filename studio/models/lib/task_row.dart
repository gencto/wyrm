import 'package:freezed_annotation/freezed_annotation.dart';

part 'task_row.freezed.dart';

@freezed
abstract class TaskRow with _$TaskRow {
  /// One row of a `TaskSuggestion`: a node the same change may be made
  /// for (`~state.suggestions[].rows[]`, ADR 0049 amendment).
  const factory TaskRow({
    /// The full node key; what goes into `ask {context}` when ticked.
    required String key,
    required String label,
    @Default('') String detail,
  }) = _TaskRow;
}
