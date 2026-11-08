import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/task_event.dart';

import '../../app_state.dart';
import '../../common/action.dart';

/// Appends [event] to the conversation of task [id].
class AddTaskEventAction extends Action {
  AddTaskEventAction(this.id, this.event);

  final String id;
  final TaskEvent event;

  @override
  AppState reduce() {
    final list = state.tasks.events[id] ?? const IListConst<TaskEvent>([]);
    return state.copyWith.tasks(
      events: state.tasks.events.add(id, list.add(event)),
    );
  }
}
