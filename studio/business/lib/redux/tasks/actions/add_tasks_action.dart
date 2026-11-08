import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/agent_task.dart';

import '../../app_state.dart';
import '../../common/action.dart';

/// Puts [AgentTask]s into the `tasks` table, keyed by `id`.
///
/// With [replace] the table and its view become exactly these items, in this
/// order (a fresh read of the whole list); without it the items are merged in
/// and a new id is appended to the view.
class AddTasksAction extends Action {
  AddTasksAction(this._items, {this.replace = false});

  final IList<AgentTask> _items;
  final bool replace;

  @override
  AppState reduce() {
    final byId = IMap<String, AgentTask>.fromValues(
      values: _items,
      keyMapper: (item) => item.id,
    );
    if (replace) {
      return state.copyWith.tasks(
        table: byId,
        view: [for (final item in _items) item.id].lock,
      );
    }
    final table = state.tasks.table;
    final view = state.tasks.view;
    return state.copyWith.tasks(
      table: table.addAll(byId),
      view: view.addAll([
        for (final item in _items)
          if (!table.containsKey(item.id)) item.id,
      ]),
    );
  }
}
