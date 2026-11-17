import 'package:models/explorer_tab.dart';

import '../../app_state.dart';
import '../../common/action.dart';
import 'retrieve_audit_action.dart';
import 'retrieve_history_action.dart';
import 'set_tab_action.dart';

/// A tab of the node on screen is picked: it shows at once; History then
/// reads the point's history, Audit the node's audit (when the user may
/// read it), and this action ends when the read has answered.
class OpenExplorerTabAction extends Action {
  OpenExplorerTabAction(this.tab);

  final ExplorerTab tab;

  @override
  Future<AppState?> reduce() async {
    if (tab != nodes.tab) {
      dispatchSync(SetTabAction(tab));
    }
    final sel = nodes.selectedNode;
    switch (tab) {
      case ExplorerTab.history:
        if (nodes.point case final p?) {
          await dispatchAndWait(RetrieveHistoryAction(p));
        }
      case ExplorerTab.audit:
        if (sel != null && site.readsAudit) {
          await dispatchAndWait(RetrieveAuditAction(sel));
        }
      case ExplorerTab.points ||
          ExplorerTab.children ||
          ExplorerTab.params ||
          ExplorerTab.actions:
        break;
    }
    return null;
  }
}
