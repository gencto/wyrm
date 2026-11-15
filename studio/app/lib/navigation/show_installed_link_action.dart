import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/nodes/actions/set_selected_node_action.dart';

import 'go_action.dart';

/// *Open in Explorer* of an install: the new link's branch [key] is
/// selected, then Add a link closes onto the screen below. One intent, one
/// dispatch (studio-rules §9); the selection notifies once, the route
/// change is the router's.
class ShowInstalledLinkAction extends ReduxAction<AppState> {
  ShowInstalledLinkAction(this.key);

  final String key;

  @override
  AppState? reduce() {
    dispatchSync(SetSelectedNodeAction(key));
    dispatchSync(GoAction.pop());
    return null;
  }
}
