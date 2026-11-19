import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import '../../app_state.dart';
import '../../common/action.dart';
import '../../live/actions/unwatch_keys_action.dart';
import '../../live/actions/watch_keys_action.dart';

/// The keys the Assistant watches now (`assistant.watched`): those a
/// finished plan touched, whose values its Result card shows. The new keys
/// are watched, then the ones it watched before are unwatched, so a key in
/// both keeps its subscription. Empty when the tab is hidden.
///
/// What is watched is kept in the store, not beside it: `onHide` and a
/// site switch unwatch exactly these keys.
class SetWatchedAction extends Action {
  SetWatchedAction(IList<String> this._watched);

  /// The keys the tab shows now ([AssistantScreen.assistantWatch]), read
  /// when it runs; nothing while the tab is hidden.
  SetWatchedAction.shown() : _watched = null;

  final IList<String>? _watched;

  @override
  AppState? reduce() {
    final watched = _watched ?? assistantWatch.lock;
    if (_watched == null && !assistant.shown) {
      return null;
    }
    final was = assistant.watched;
    if (was.length == watched.length && was.every(watched.contains)) {
      return null;
    }
    // the watches and the list are one change on screen
    dispatchSync(WatchKeysAction(watched), notify: false);
    dispatchSync(UnwatchKeysAction(was), notify: false);
    return state.copyWith.assistant(watched: watched);
  }
}
