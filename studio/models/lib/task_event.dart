import 'package:freezed_annotation/freezed_annotation.dart';

import 'task_event_kind.dart';
import 'task_state.dart';

part 'task_event.freezed.dart';

/// One line of a task's conversation: what was asked, what the model said,
/// what it read (a tool), a state it reached, an error.
@freezed
abstract class TaskEvent with _$TaskEvent {
  const factory TaskEvent({
    required TaskEventKind kind,
    @Default('') String text,

    /// The state reached, for [TaskEventKind.state].
    TaskState? state,
    DateTime? time,
  }) = _TaskEvent;
}
