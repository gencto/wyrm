import '../../app_state.dart';
import '../../common/action.dart';

/// Watches [keys] (keys or `*` patterns): one more reader of each in
/// `live.watched`, and a subscription for each that had none. Dispatched when
/// a screen with these keys is shown.
///
/// `watched` counts readers, so two screens on one key (a tab and an
/// inspector) each unwatch their own without closing the other's.
class WatchKeysAction extends Action {
  WatchKeysAction(this.keys);

  final Iterable<String> keys;

  @override
  AppState? reduce() {
    if (keys.isEmpty) {
      return null;
    }
    var watched = state.live.watched;
    for (final k in keys.toSet()) {
      watched = watched.add(k, (watched[k] ?? 0) + 1);
    }
    deps.liveValues.sync(watched.keys);
    return state.copyWith.live(watched: watched);
  }
}
