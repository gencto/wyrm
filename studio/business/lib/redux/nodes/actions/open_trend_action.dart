import 'package:models/explorer_tab.dart';

import '../../app_state.dart';
import '../../common/action.dart';
import 'retrieve_history_action.dart';
import 'select_node_action.dart';
import 'set_tab_action.dart';
import 'show_node_action.dart';
import 'show_point_action.dart';

/// Opens the trend of the point [key] in Explorer: its node selected, the
/// point in the inspector, the History tab, in one state; then the node's
/// reads and the point's history run in parallel (spec `trend.md` §4,
/// Explorer "View History"). The caller goes to Explorer.
class OpenTrendAction extends Action {
  OpenTrendAction(this.key);

  final String key;

  @override
  Future<AppState?> reduce() async {
    final cut = key.lastIndexOf('/');
    if (cut <= 0) {
      return null;
    }
    final before = nodes.selectedNode;
    final node = key.substring(0, cut);
    dispatchSync(ShowNodeAction(node), notify: false);
    dispatchSync(ShowPointAction(key), notify: false);
    // the one state shown: the node, the point and the tab
    dispatchSync(SetTabAction(ExplorerTab.history));
    await Future.wait([
      for (final a in SelectNodeAction.readsOf(state, node, before: before))
        dispatchAndWait(a),
      dispatchAndWait(RetrieveHistoryAction(key)),
    ]);
    return null;
  }
}
