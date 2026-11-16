import 'package:async_redux/async_redux.dart';

import '../../../wyrm/flow_view/flow_view.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import '../../live/actions/unwatch_keys_action.dart';
import '../../live/actions/watch_keys_action.dart';
import '../../nodes/actions/retrieve_details_action.dart';
import 'preview_flow_action.dart';

/// What the flow editor follows went from [was] to [now]: the keys it
/// watches (the Tree tab's open nodes, the points its blocks read and
/// write, the flow's own `~val`), the draft it runs as a preview (the
/// service debounces it), and the nodes whose `~meta` its action blocks
/// wait for. One step for all three.
class FollowFlowEditorAction extends Action {
  FollowFlowEditorAction(this.was, this.now);

  final FlowFollow was;
  final FlowFollow now;

  @override
  AppState? reduce() {
    if (was.watch != now.watch) {
      // The new keys first: a key in both is never let go in between.
      dispatchSync(WatchKeysAction(now.watch), notify: false);
      dispatchSync(UnwatchKeysAction(was.watch), notify: false);
    }
    if (was.run != now.run) {
      dispatchSync(PreviewFlowAction(), notify: false);
    }
    // Read once per node, quietly; it brings its own state.
    if (was.details != now.details && now.details.isNotEmpty) {
      _start(RetrieveDetailsAction(now.details.toList()));
    }
    return was.watch != now.watch || was.run != now.run ? state : null;
  }

  /// Starts [action] and does not wait for it: it brings its own state
  /// (and its own waiting state, where it has one).
  void _start(ReduxAction<AppState> action) => dispatch(action);
}
