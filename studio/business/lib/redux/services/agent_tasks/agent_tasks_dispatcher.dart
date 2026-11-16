import 'package:async_redux/async_redux.dart';
import 'package:models/task_state.dart';

import '../../app_state.dart';
import '../../tasks/actions/task_state_heard_action.dart';
import 'agent_tasks.dart';

/// Writes a task's state and the step of its run into the `tasks` table,
/// keeping what is known of the rest of its record.
class AgentTasksDispatcher implements AgentTasksServiceListener {
  AgentTasksDispatcher({required this._store});

  final Store<AppState> _store;

  /// The step a task's run is at, the latest one that ended, the number of
  /// suggestions, whether the model reviews the run and the task that
  /// replaced it, as last heard: when any moves, the record has something
  /// new (a review ends with the state still `failed`).
  final _seen = <String, (int, int, int, int, bool, String?)>{};

  /// A stream listener does not wait (studio-rules §1): what was heard is
  /// one action, which reads the task's record again when it is the one on
  /// screen.
  @override
  void onTaskState(
    String id,
    TaskState state, {
    int step = 0,
    int finished = 0,
    int suggestions = 0,
    int findings = 0,
    bool reviewing = false,
    String? replacedBy,
  }) => _store.dispatch(
    TaskStateHeardAction(
      id,
      state,
      moved: _moved(id, (
        step,
        finished,
        suggestions,
        findings,
        reviewing,
        replacedBy,
      )),
      step: step,
      reviewing: reviewing,
      replacedBy: replacedBy,
    ),
  );

  /// Whether the run of [id] moved since it was last heard ([now] kept).
  bool _moved(String id, (int, int, int, int, bool, String?) now) {
    final moved = _seen[id] != now;
    _seen[id] = now;
    return moved;
  }
}
