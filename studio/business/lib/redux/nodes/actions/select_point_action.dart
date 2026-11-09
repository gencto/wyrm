import 'dart:async';

import '../../app_state.dart';
import '../../common/action.dart';
import 'retrieve_details_action.dart';
import 'retrieve_history_action.dart';

/// Shows the point [key] in the inspector (a click on its row); the node on
/// screen stays. Null shows the node itself (docs/design/specs/explorer.md
/// §4 "nothing selected").
class SelectPointAction extends Action {
  SelectPointAction(this.key);

  final String? key;

  @override
  AppState? reduce() {
    final k = key;
    if (k == nodes.point) {
      return null;
    }
    if (k != null) {
      if (!nodes.detail.containsKey(k)) {
        unawaited(dispatchAndWait(RetrieveDetailsAction([k])));
      }
      if (nodes.tab == 'history') {
        unawaited(dispatchAndWait(RetrieveHistoryAction(k)));
      }
    }
    return state.copyWith.nodes(point: k, anchor: k ?? nodes.anchor);
  }
}
