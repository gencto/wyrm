import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import '../../app_state.dart';
import '../../common/action.dart';
import 'toggle_node_action.dart';

/// The selection part of `SelectNodeAction`, shown at once in one state:
/// [key]'s parents open in the tree, it is listed live, and the selected
/// action, the checked rows and the point in the inspector are cleared (a
/// point: its parent with the point in the inspector). It reads nothing.
class ShowNodeAction extends Action {
  ShowNodeAction(this.key);

  final String key;

  @override
  AppState reduce() {
    final asPoint = state.nodes.table[key]?.type != null;
    final node = asPoint ? key.substring(0, key.lastIndexOf('/')) : key;
    final parts = node.split('/');
    for (var i = 3; i < parts.length; i++) {
      dispatchSync(
        ToggleNodeAction(parts.sublist(0, i).join('/'), open: true),
        // shown with the selection, in the state returned below
        notify: false,
      );
    }
    // The selected node's children are its points on screen: list them
    // live, and stop listing the one selected before unless it is open.
    final before = state.nodes.selectedNode;
    if (before != null &&
        before != node &&
        !state.nodes.expanded.contains(before)) {
      deps.treeWatch.close(before);
    }
    deps.treeWatch.open(node);
    final same = node == before;
    return state.copyWith.nodes(
      selectedNode: node,
      action: null,
      point: asPoint ? key : (same ? state.nodes.point : null),
      anchor: asPoint ? key : (same ? state.nodes.anchor : null),
      checked: same ? state.nodes.checked : const ISetConst({}),
      pointFilter: same ? state.nodes.pointFilter : '',
    );
  }
}
