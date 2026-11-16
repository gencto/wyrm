import 'package:async_redux/async_redux.dart';

import '../../app_state.dart';
import '../../common/action.dart';
import '../../nodes/actions/retrieve_details_action.dart';
import '../../nodes/actions/toggle_node_action.dart';

/// A node of the palette's Tree tab opens or closes (spec §18). A node's
/// actions are in its own `~meta`: read once, when it is first opened here
/// (the tree's lists do not carry them).
class ToggleTreeNodeAction extends Action {
  ToggleTreeNodeAction(this.key);

  final String key;

  @override
  AppState? reduce() {
    final opening = !nodes.expanded.contains(key);
    dispatchSync(ToggleNodeAction(key));
    if (opening && !nodes.detail.containsKey(key)) {
      // Its own read; it brings its own state.
      _start(RetrieveDetailsAction([key]));
    }
    return null;
  }

  /// Starts [action] and does not wait for it: it brings its own state
  /// (and its own waiting state, where it has one).
  void _start(ReduxAction<AppState> action) => dispatch(action);
}
