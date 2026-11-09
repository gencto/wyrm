import 'dart:async';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/node_info.dart';

import '../../../wyrm/points.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import 'retrieve_details_action.dart';

/// Puts [NodeInfo]s into the `nodes` table, keyed by `key`.
///
/// With [replace] the table and its view become exactly these items, in this
/// order (a fresh read of the whole list); without it the items are merged in
/// and a new id is appended to the view. A point of the node on screen that
/// arrives this way (added or changed later) and has no full meta yet gets
/// it read, like the first list's points (the table's columns).
class AddNodesAction extends Action {
  AddNodesAction(this._items, {this.replace = false});

  final IList<NodeInfo> _items;
  final bool replace;

  @override
  AppState reduce() {
    final byId = IMap<String, NodeInfo>.fromValues(
      values: _items,
      keyMapper: (item) => item.key,
    );
    if (replace) {
      return state.copyWith.nodes(
        table: byId,
        view: [for (final item in _items) item.key].lock,
      );
    }
    final sel = state.nodes.selectedNode;
    final unread = [
      for (final item in _items)
        if (sel != null &&
            item.key == '$sel/${item.name}' &&
            isPoint(item) &&
            !state.nodes.detail.containsKey(item.key))
          item.key,
    ];
    if (unread.isNotEmpty) {
      unawaited(dispatchAndWait(RetrieveDetailsAction(unread)));
    }
    final table = state.nodes.table;
    final view = state.nodes.view;
    return state.copyWith.nodes(
      table: table.addAll(byId),
      view: view.addAll([
        for (final item in _items)
          if (!table.containsKey(item.key)) item.key,
      ]),
    );
  }
}
