import '../../app_state.dart';
import '../../common/action.dart';

/// Adds tree rows to a selection for Copy keys only (⌘-click toggles one,
/// Shift-click adds the rows from the selected node to [key];
/// docs/design/specs/explorer.md §6). The node on screen does not change.
class MarkNodesAction extends Action {
  /// Marks or unmarks [key].
  MarkNodesAction.toggle(this.key) : order = const [];

  /// Marks the rows of [order] from the selected node to [key].
  MarkNodesAction.range(this.key, this.order);

  final String key;

  /// The keys of the tree rows on screen, in their order.
  final List<String> order;

  @override
  AppState? reduce() {
    final marked = nodes.marked;
    if (order.isEmpty) {
      return state.copyWith.nodes(
        marked: marked.contains(key) ? marked.remove(key) : marked.add(key),
      );
    }
    final to = order.indexOf(key);
    if (to < 0) {
      return null;
    }
    final from = order.indexOf(nodes.selectedNode ?? key);
    final (a, b) = from < 0 ? (to, to) : (from < to ? (from, to) : (to, from));
    return state.copyWith.nodes(
      marked: marked.addAll(order.sublist(a, b + 1)),
    );
  }
}
