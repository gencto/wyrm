import 'package:models/explorer_tab.dart';
import 'package:wyrm_client/wyrm_client.dart' show Perm;

import '../../app_state.dart';
import '../../common/action.dart';
import 'retrieve_audit_action.dart';
import 'retrieve_history_action.dart';

/// A tab of the node on screen is picked: History reads the point's
/// history, Audit the node's audit (when the user may read it).
class OpenExplorerTabAction extends Action {
  OpenExplorerTabAction(this.tab);

  final ExplorerTab tab;

  @override
  AppState? reduce() {
    final sel = nodes.selectedNode;
    // the read starts with its own wait; the tab shows now
    dispatchAll([
      ...switch (tab) {
        ExplorerTab.history => [
          if (nodes.point case final p?) RetrieveHistoryAction(p),
        ],
        ExplorerTab.audit => [
          if (sel != null &&
              site.can(Perm.config.wire, '${site.root}/sys/audit'))
            RetrieveAuditAction(sel),
        ],
        ExplorerTab.points ||
        ExplorerTab.children ||
        ExplorerTab.params ||
        ExplorerTab.actions => const <Action>[],
      },
    ]);
    return tab == nodes.tab ? null : state.copyWith.nodes(tab: tab);
  }
}
