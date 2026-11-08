import 'dart:async';

import '../../app_state.dart';
import '../../common/action.dart';
import 'retrieve_history_action.dart';
import 'retrieve_node_detail_action.dart';
import 'toggle_node_action.dart';

/// Selects [key] in Explorer: its parents open in the tree, its full meta is
/// read, a point's history is read; the selected action is cleared.
class SelectNodeAction extends Action {
  SelectNodeAction(this.key);

  final String key;

  @override
  AppState reduce() {
    final parts = key.split('/');
    for (var i = 3; i < parts.length; i++) {
      dispatchSync(ToggleNodeAction(parts.sublist(0, i).join('/'), open: true));
    }
    // The selected node's children are its points on screen: list them
    // live, and stop listing the one selected before unless it is open.
    final before = state.nodes.selectedNode;
    if (before != null &&
        before != key &&
        !state.nodes.expanded.contains(before)) {
      deps.treeWatch.close(before);
    }
    deps.treeWatch.open(key);
    unawaited(dispatchAndWait(RetrieveNodeDetailAction(key)));
    if (state.nodes.table[key]?.type != null) {
      unawaited(dispatchAndWait(RetrieveHistoryAction(key)));
    }
    return state.copyWith.nodes(selectedNode: key, action: null);
  }
}
