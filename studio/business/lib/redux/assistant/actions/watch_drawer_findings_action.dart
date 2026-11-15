import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import '../../app_state.dart';
import '../../common/action.dart';
import '../../live/actions/unwatch_keys_action.dart';
import '../../live/actions/watch_keys_action.dart';

/// The nodes of *What I found* moved (another task, a new finding): while
/// the drawer is shown it watches the new ones, then lets the old ones go,
/// so a key in both keeps its subscription. One state at the end.
class WatchDrawerFindingsAction extends Action {
  @override
  AppState? reduce() {
    final was = assistant.drawerWatched;
    final keys = drawerFindingKeys;
    if (!assistant.drawerShown ||
        (was.length == keys.length && was.every(keys.contains))) {
      return null;
    }
    dispatchSync(WatchKeysAction(keys), notify: false);
    dispatchSync(UnwatchKeysAction(was), notify: false);
    return state.copyWith.assistant(drawerWatched: keys.lock);
  }
}
