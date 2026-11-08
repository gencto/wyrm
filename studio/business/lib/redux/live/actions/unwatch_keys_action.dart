import '../../app_state.dart';
import '../../common/action.dart';

/// Removes [keys] from `live.watched`, closes their subscriptions and drops
/// their last values. Dispatched by a connector's `onDispose`.
class UnwatchKeysAction extends Action {
  UnwatchKeysAction(this.keys);

  final Iterable<String> keys;

  @override
  AppState? reduce() {
    final watched = state.live.watched.removeAll(keys);
    if (watched == state.live.watched) {
      return null;
    }
    deps.liveValues.sync(watched);
    // A pattern's values are kept by their own keys; drop those under it.
    final gone = keys.toSet();
    final values = state.live.values.removeWhere(
      (k, _) => gone.contains(k) || gone.any((p) => _matches(p, k)),
    );
    return state.copyWith.live(watched: watched, values: values);
  }
}

/// [key] matches [pattern] of `*` (one segment) and `**` (any segments).
bool _matches(String pattern, String key) {
  if (!pattern.contains('*')) {
    return false;
  }
  final p = pattern.split('/');
  final k = key.split('/');
  bool at(int i, int j) {
    if (i == p.length) {
      return j == k.length;
    }
    if (p[i] == '**') {
      for (var n = j; n <= k.length; n++) {
        if (at(i + 1, n)) {
          return true;
        }
      }
      return false;
    }
    if (j == k.length) {
      return false;
    }
    return (p[i] == '*' || p[i] == k[j]) && at(i + 1, j + 1);
  }

  return at(0, 0);
}
