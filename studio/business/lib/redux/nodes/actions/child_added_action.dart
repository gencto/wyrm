import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/node_info.dart';

import '../../../wyrm/points.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import 'add_nodes_action.dart';
import 'children_listed_action.dart';
import 'retrieve_details_action.dart';

/// A live list of [parent] added or changed [child] (the tree watch): the
/// table shows it at once ([AddNodesAction]); a point of the node on screen
/// with no full meta yet has it read, and an enum its value names; this
/// action ends when they have answered.
class ChildAddedAction extends Action {
  ChildAddedAction(this.parent, this.child);

  final String parent;
  final NodeInfo child;

  @override
  Future<AppState?> reduce() async {
    final unread =
        state.nodes.selectedNode == parent &&
        isPoint(child) &&
        !state.nodes.detail.containsKey(child.key);
    dispatchSync(AddNodesAction([child].lock));
    await Future.wait(
      [
        if (unread) RetrieveDetailsAction([child.key]),
        ...ChildrenListedAction.enumNameReads([child]),
      ].map(dispatchAndWait),
    );
    return null;
  }
}
