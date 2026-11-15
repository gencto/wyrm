import 'package:models/explorer_tab.dart';

import '../../app_state.dart';
import '../../common/action.dart';
import 'retrieve_details_action.dart';
import 'retrieve_history_action.dart';

/// Shows the point [key] in the inspector (a click on its row); the node on
/// screen stays. Null shows the node itself (docs/design/specs/explorer.md
/// §4 "nothing selected").
class SelectPointAction extends Action {
  SelectPointAction(this.key) : _toggle = false;

  /// A click on [row]: shows its point, or the node again when the point
  /// is the one shown already.
  SelectPointAction.toggle(String row) : key = row, _toggle = true;

  final String? key;
  final bool _toggle;

  @override
  AppState? reduce() {
    final k = _toggle && key == nodes.point ? null : key;
    if (k == nodes.point) {
      return null;
    }
    if (k != null) {
      // started in parallel, each with its own wait; the point shows now
      dispatchAll([
        if (!nodes.detail.containsKey(k)) RetrieveDetailsAction([k]),
        if (nodes.tab == ExplorerTab.history) RetrieveHistoryAction(k),
      ]);
    }
    return state.copyWith.nodes(point: k, anchor: k ?? nodes.anchor);
  }
}
