import 'package:freezed_annotation/freezed_annotation.dart';

part 'task_event.freezed.dart';

/// One line of a task's conversation: what was asked, what the model said,
/// what it read (a tool), a state it reached, an error.
@freezed
abstract class TaskEvent with _$TaskEvent {
  const factory TaskEvent({
    /// `ask`, `text`, `tool`, `state`, `error`.
    required String kind,
    @Default('') String text,
    DateTime? time,
  }) = _TaskEvent;
}
