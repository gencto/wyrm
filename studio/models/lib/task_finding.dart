import 'package:freezed_annotation/freezed_annotation.dart';

part 'task_finding.freezed.dart';

@freezed
abstract class TaskFinding with _$TaskFinding {
  /// What the model read about one node (`~state.findings[]`, ADR 0049
  /// amendment 2): a row of *What I found* in the Explorer drawer. [label]
  /// and [detail] are the model's words; the row's mark comes from the
  /// node's live value, never from them.
  const factory TaskFinding({
    /// The full node key (one the agent link checked the asker may read).
    required String key,
    required String label,
    @Default('') String detail,
  }) = _TaskFinding;
}
