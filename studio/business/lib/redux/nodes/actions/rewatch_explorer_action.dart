import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import '../../../wyrm/explorer.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import '../../live/actions/unwatch_keys_action.dart';
import '../../live/actions/watch_keys_action.dart';

/// The keys Explorer shows changed while its tab is shown (another node, a
/// viewer opened): the new ones are watched and the old ones let go, in
/// one state. Nothing while the tab is hidden or the keys are the same.
class RewatchExplorerAction extends Action {
  @override
  AppState? reduce() {
    final before = nodes.watching;
    if (before == null) {
      return null;
    }
    final now = ExplorerView(state).watchKeys;
    if (now.length == before.length && now.every(before.contains)) {
      return null;
    }
    // Watched before the old ones go, so a key in both stays subscribed.
    dispatchSync(WatchKeysAction(now), notify: false);
    dispatchSync(UnwatchKeysAction(before), notify: false);
    return state.copyWith.nodes(watching: now.lock);
  }
}
