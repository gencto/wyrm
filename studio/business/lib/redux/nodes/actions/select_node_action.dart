import 'package:models/explorer_tab.dart';
import 'package:wyrm_client/wyrm_client.dart' show Perm;

import '../../../wyrm/points.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import 'retrieve_audit_action.dart';
import 'retrieve_details_action.dart';
import 'retrieve_history_action.dart';
import 'retrieve_node_detail_action.dart';
import 'show_node_action.dart';

/// Selects [key] in Explorer: the selection shows at once
/// ([ShowNodeAction], one state), then the node's reads run in parallel and
/// this action ends when they have answered: its full meta, quietly the
/// meta of its points and of its parent (the connection's host and port in
/// a device's subtitle), a point's history, and on the Audit tab its audit
/// (when the user may read the site's audit).
///
/// A point is not a node of its own: selecting one (search, a link) shows
/// its parent with the point in the inspector (docs/design/specs/
/// explorer.md §3).
class SelectNodeAction extends Action {
  SelectNodeAction(this.key);

  final String key;

  @override
  Future<AppState?> reduce() async {
    final before = nodes.selectedNode;
    dispatchSync(ShowNodeAction(key));
    await Future.wait([
      for (final a in readsOf(state, key, before: before)) dispatchAndWait(a),
    ]);
    return null;
  }

  /// The reads of selecting [key] in [s] (the state with the selection
  /// shown), the node before being [before].
  static List<Action> readsOf(AppState s, String key, {String? before}) {
    final node = s.nodes.selectedNode ?? key;
    final parts = node.split('/');
    return [
      RetrieveNodeDetailAction(node, quiet: true),
      RetrieveDetailsAction([
        if (parts.length > 4) parts.sublist(0, parts.length - 1).join('/'),
        for (final n in s.nodes.table.values)
          if (n.key.startsWith('$node/') &&
              !n.key.substring(node.length + 1).contains('/') &&
              isPoint(n))
            n.key,
      ]),
      if (key != node) RetrieveHistoryAction(key),
      if (node != before &&
          s.nodes.tab == ExplorerTab.audit &&
          SelectSite(s)
              .can(Perm.config.wire, '${SelectSite(s).root}/sys/audit'))
        RetrieveAuditAction(node),
    ];
  }
}
