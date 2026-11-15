import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/node_info.dart';

import '../../app_state.dart';
import '../../common/action.dart';

/// The whole child list of [parent] (a list's first answer): children no
/// longer in it leave the table with everything below them, and [parent]
/// joins `nodes.listed` — its list has answered, even when it is empty.
/// `ChildrenListedAction` then reads the points' meta.
class SetChildrenAction extends Action {
  SetChildrenAction(this.parent, this.children);

  final String parent;
  final IList<NodeInfo> children;

  @override
  AppState reduce() {
    final keep = {for (final c in children) c.key};
    final prefix = '$parent/';
    bool stale(String k) =>
        k.startsWith(prefix) &&
        !keep.contains(k) &&
        !keep.any((c) => k.startsWith('$c/'));
    final table = state.nodes.table.removeWhere((k, _) => stale(k)).addEntries([
      for (final c in children) MapEntry(c.key, c),
    ]);
    final view = state.nodes.view.removeWhere(stale);
    return state.copyWith.nodes(
      table: table,
      view: view.addAll([
        for (final c in children)
          if (!view.contains(c.key)) c.key,
      ]),
      expanded: state.nodes.expanded.removeWhere(stale),
      listed: state.nodes.listed.add(parent),
      listFailed: state.nodes.listFailed.remove(parent),
    );
  }
}
