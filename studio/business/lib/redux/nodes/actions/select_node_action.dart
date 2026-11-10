import 'dart:async';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import '../../../wyrm/points.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import 'retrieve_details_action.dart';
import 'retrieve_history_action.dart';
import 'retrieve_node_detail_action.dart';
import 'toggle_node_action.dart';

/// Selects [key] in Explorer: its parents open in the tree, its full meta is
/// read, and the meta of its points and of its parent (the connection's
/// host and port in a device's subtitle) is read quietly; the selected
/// action, the checked rows and the point in the inspector are cleared.
///
/// A point is not a node of its own: selecting one (search, a link) shows
/// its parent with the point in the inspector (docs/design/specs/
/// explorer.md §3).
class SelectNodeAction extends Action {
  SelectNodeAction(this.key);

  final String key;

  @override
  AppState reduce() {
    final asPoint = state.nodes.table[key]?.type != null;
    final node = asPoint ? key.substring(0, key.lastIndexOf('/')) : key;
    final parts = node.split('/');
    for (var i = 3; i < parts.length; i++) {
      dispatchSync(ToggleNodeAction(parts.sublist(0, i).join('/'), open: true));
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
    unawaited(dispatchAndWait(RetrieveNodeDetailAction(node, quiet: true)));
    unawaited(
      dispatchAndWait(
        RetrieveDetailsAction([
          if (parts.length > 4) parts.sublist(0, parts.length - 1).join('/'),
          for (final n in state.nodes.table.values)
            if (n.key.startsWith('$node/') &&
                !n.key.substring(node.length + 1).contains('/') &&
                isPoint(n))
              n.key,
        ]),
      ),
    );
    if (asPoint) {
      unawaited(dispatchAndWait(RetrieveHistoryAction(key)));
    }
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
