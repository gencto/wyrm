import '../../app_state.dart';
import '../../common/action.dart';

/// Opens or closes [key] in the tree: an open node is listed live
/// (`TreeWatchService`), a closed one stops being listed with everything
/// under it.
class ToggleNodeAction extends Action {
  ToggleNodeAction(this.key, {this.open});

  final String key;

  /// Force open (true) or closed (false); null toggles.
  final bool? open;

  @override
  AppState? reduce() {
    final isOpen = state.nodes.expanded.contains(key);
    final want = open ?? !isOpen;
    if (want == isOpen) {
      return null;
    }
    if (want) {
      deps.treeWatch.open(key);
      return state.copyWith.nodes(expanded: state.nodes.expanded.add(key));
    }
    deps.treeWatch.close(key);
    return state.copyWith.nodes(
      expanded: state.nodes.expanded.removeWhere(
        (k) => k == key || k.startsWith('$key/'),
      ),
    );
  }
}
