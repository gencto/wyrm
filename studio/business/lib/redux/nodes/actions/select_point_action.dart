import 'package:models/explorer_tab.dart';

import '../../app_state.dart';
import '../../common/action.dart';
import 'retrieve_details_action.dart';
import 'retrieve_history_action.dart';
import 'show_point_action.dart';

/// Shows the point [key] in the inspector (a click on its row); the node on
/// screen stays. Null shows the node itself (docs/design/specs/explorer.md
/// §4 "nothing selected"). The point shows at once ([ShowPointAction]);
/// then its meta (when not read yet) and, on the History tab, its history
/// are read in parallel, and this action ends when they have answered.
class SelectPointAction extends Action {
  SelectPointAction(this.key) : _toggle = false;

  /// A click on [row]: shows its point, or the node again when the point
  /// is the one shown already.
  SelectPointAction.toggle(String row) : key = row, _toggle = true;

  final String? key;
  final bool _toggle;

  @override
  Future<AppState?> reduce() async {
    final k = _toggle && key == nodes.point ? null : key;
    if (k == nodes.point) {
      return null;
    }
    dispatchSync(ShowPointAction(k));
    if (k != null) {
      await Future.wait([
        if (!nodes.detail.containsKey(k))
          dispatchAndWait(RetrieveDetailsAction([k])),
        if (nodes.tab == ExplorerTab.history)
          dispatchAndWait(RetrieveHistoryAction(k)),
      ]);
    }
    return null;
  }
}
