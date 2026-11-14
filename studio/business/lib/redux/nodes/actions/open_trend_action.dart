import 'dart:async';

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
    dispatchSync(SelectNodeAction(key.substring(0, cut)));
    dispatchSync(SetTabAction('history'));
    dispatchSync(SelectPointAction(key));
    unawaited(dispatchAndWait(RetrieveHistoryAction(key)));
    return null;
  }
}
