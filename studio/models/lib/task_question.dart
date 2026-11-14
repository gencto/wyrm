import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'task_option.dart';

part 'task_question.freezed.dart';

@freezed
abstract class TaskQuestion with _$TaskQuestion {
  /// A question the assistant asks the person (`tasks/<id>` `~state`
  /// `questions[]`, ADR 0049 §5).
  const factory TaskQuestion({
    /// `q1`, `q2`, …: unique in the task.
    required String id,
    required String text,
    @Default(IListConst([])) IList<TaskOption> options,

    /// Several options may be picked.
    @Default(false) bool multiple,

    /// The person may answer in their own words.
    @Default(false) bool freeText,

    /// It was answered (an answer of no option and no words too).
    @Default(false) bool answered,

    /// The option ids that were picked.
    @Default(IListConst([])) IList<String> picked,

    /// The person's own words, when the answer was text.
    String? words,
  }) = _TaskQuestion;
}
