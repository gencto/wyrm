import 'package:models/explorer_tab.dart';

import '../../app_state.dart';
import '../../common/action.dart';
import 'retrieve_history_action.dart';
import 'select_node_action.dart';
import 'select_point_action.dart';
import 'set_tab_action.dart';

/// Opens the trend of the point [key] in Explorer: its node selected, the
/// point in the inspector, the History tab, its history read (spec
/// `trend.md` §4, Explorer "View History"). The caller goes to Explorer.
class OpenTrendAction extends Action {
  OpenTrendAction(this.key);

  final String key;

  @override
  AppState? reduce() {
    final cut = key.lastIndexOf('/');
    if (cut <= 0) {
      return null;
    }
    // One state at the end: the node, the tab and the point together.
    dispatchSync(SelectNodeAction(key.substring(0, cut)), notify: false);
    dispatchSync(SetTabAction(ExplorerTab.history), notify: false);
    dispatchSync(SelectPointAction(key), notify: false);
    dispatchAll([RetrieveHistoryAction(key)]);
    return state.copyWith.nodes(
      tab: ExplorerTab.history,
      point: key,
      anchor: key,
    );
  }
}
