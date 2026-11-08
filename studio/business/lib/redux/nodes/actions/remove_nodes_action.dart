import '../../app_state.dart';
import '../../common/action.dart';

/// Removes [key] and every node below it.
class RemoveNodesAction extends Action {
  RemoveNodesAction(this.key);

  final String key;

  @override
  AppState reduce() {
    bool gone(String k) => k == key || k.startsWith('$key/');
    final selected = state.nodes.selectedNode;
    return state.copyWith.nodes(
      table: state.nodes.table.removeWhere((k, _) => gone(k)),
      view: state.nodes.view.removeWhere(gone),
      expanded: state.nodes.expanded.removeWhere(gone),
      selectedNode: selected != null && gone(selected) ? null : selected,
    );
  }
}
