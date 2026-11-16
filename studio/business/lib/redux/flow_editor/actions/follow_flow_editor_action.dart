import '../../../wyrm/flow_view/flow_view.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import '../../live/actions/unwatch_keys_action.dart';
import '../../live/actions/watch_keys_action.dart';
import '../../nodes/actions/retrieve_details_action.dart';
import 'preview_flow_action.dart';
import 'validate_flow_action.dart';

/// What the flow editor follows went from [was] to [now]: the keys it
/// watches (the Tree tab's open nodes, the points its blocks read and
/// write, the flow's own `~val`), the draft it runs as a preview (the
/// service debounces it) and the engine checks ([ValidateFlowAction], also
/// debounced), and the nodes whose `~meta` its action blocks wait for. One
/// step for all: every edit of the definition (its layout aside) is
/// followed here, once the page drew it.
///
/// Rebuilds, decided: the watches change nothing drawn (`notify: false`);
/// the preview's step is the one that notifies. The reads that follow bring
/// their own states; this action ends when they have answered and changes
/// no state itself (`null`).
class FollowFlowEditorAction extends Action {
  FollowFlowEditorAction(this.was, this.now);

  final FlowFollow was;
  final FlowFollow now;

  @override
  Future<AppState?> reduce() async {
    final watch = was.watch != now.watch;
    final run = was.run != now.run;
    if (watch) {
      // The new keys first: a key in both is never let go in between.
      dispatchSync(WatchKeysAction(now.watch), notify: false);
      dispatchSync(UnwatchKeysAction(was.watch), notify: !run);
    }
    if (run) {
      dispatchSync(PreviewFlowAction());
    }
    await Future.wait([
      // Read once per node, quietly.
      if (was.details != now.details && now.details.isNotEmpty)
        dispatchAndWait(RetrieveDetailsAction(now.details.toList())),
      if (run) dispatchAndWait(ValidateFlowAction()),
    ]);
    return null;
  }
}
