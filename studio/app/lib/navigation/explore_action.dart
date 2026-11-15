import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/nodes/actions/select_node_action.dart';
import 'package:models/workspace.dart';

import 'go_action.dart';

/// Shows [key] in Explorer, one intent: the rail on Explorer, then the node
/// selected (it shows at once) and read; this action ends when the reads
/// have answered.
class ExploreAction extends ReduxAction<AppState> {
  ExploreAction(this.key);

  final String key;

  @override
  Future<AppState?> reduce() async {
    dispatchSync(GoAction.workspace(Workspace.explorer));
    await dispatchAndWait(SelectNodeAction(key));
    return null;
  }
}
