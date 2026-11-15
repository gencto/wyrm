import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import '../../app_state.dart';
import '../../common/action.dart';
import '../../live/actions/unwatch_keys_action.dart';
import '../../live/actions/watch_keys_action.dart';
import 'load_assistant_action.dart';

/// The Assistant drawer is on screen or not (Explorer's tab active and the
/// drawer open: its `TabVisibility`). Shown, it watches the nodes of the
/// task's findings for their marks (its own readers, apart from the tab's
/// `assistant.watched`) and reads the site's agent and its tasks (the tab
/// may never have been shown); hidden, it lets the nodes go.
class ShowDrawerAction extends Action {
  ShowDrawerAction({required this.shown});

  final bool shown;

  @override
  Future<AppState?> reduce() async {
    if (!shown) {
      if (!assistant.drawerShown) {
        return null;
      }
      dispatchSync(UnwatchKeysAction(assistant.drawerWatched), notify: false);
      return state.copyWith.assistant(
        drawerShown: false,
        drawerWatched: const IListConst([]),
      );
    }
    final keys = drawerFindingKeys;
    dispatchSync(WatchKeysAction(keys), notify: false);
    dispatchSync(_Shown(keys.lock));
    await dispatchAndWait(LoadAssistantAction());
    return null;
  }
}

class _Shown extends Action {
  _Shown(this.keys);

  final IList<String> keys;

  @override
  AppState reduce() =>
      state.copyWith.assistant(drawerShown: true, drawerWatched: keys);
}
