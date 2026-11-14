import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'task_row.dart';

part 'task_suggestion.freezed.dart';

@freezed
abstract class TaskSuggestion with _$TaskSuggestion {
  /// What the model offers the person to ask next (`~state.suggestions[]`,
  /// ADR 0049 amendment): a fix for the warning of plan step [step], the
  /// same change for more nodes ([rows]), or a way out of a run that
  /// stopped. Text of the model: data for a card, never a command. Picking
  /// it sends a follow-up ask.
  const factory TaskSuggestion({
    required String id,
    required String label,
    @Default('') String detail,

    /// How many changes the model expects the follow-up to plan (0:
    /// nothing changes). Its guess, not a check.
    @Default(0) int changes,

    /// The plan step (`n`) this is a fix for; null: about the task.
    int? step,
    @Default(IListConst([])) IList<TaskRow> rows,
  }) = _TaskSuggestion;
}
