import '../../app_state.dart';
import '../../common/action.dart';

/// Adds [keys] (keys or `*` patterns) to `live.watched` and subscribes to
/// them. Dispatched by a connector's `onInit` with the keys it shows.
class WatchKeysAction extends Action {
  WatchKeysAction(this.keys);

  final Iterable<String> keys;

  @override
  AppState? reduce() {
    final watched = state.live.watched.addAll(keys);
    if (watched == state.live.watched) {
      return null;
    }
    deps.liveValues.sync(watched);
    return state.copyWith.live(watched: watched);
  }
}
