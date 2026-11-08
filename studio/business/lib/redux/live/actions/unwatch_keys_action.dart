import '../../../wyrm/keys.dart';
import '../../app_state.dart';
import '../../common/action.dart';

/// One reader fewer of each of [keys]; a key nobody reads is unsubscribed and
/// its last values (under a pattern too) are dropped.
class UnwatchKeysAction extends Action {
  UnwatchKeysAction(this.keys);

  final Iterable<String> keys;

  @override
  AppState? reduce() {
    var watched = state.live.watched;
    final gone = <String>{};
    for (final k in keys.toSet()) {
      final n = watched[k];
      if (n == null) {
        continue;
      }
      if (n <= 1) {
        watched = watched.remove(k);
        gone.add(k);
      } else {
        watched = watched.add(k, n - 1);
      }
    }
    if (watched == state.live.watched) {
      return null;
    }
    deps.liveValues.sync(watched.keys);
    if (gone.isEmpty) {
      return state.copyWith.live(watched: watched);
    }
    final values = state.live.values.removeWhere(
      (k, _) => gone.any((p) => keyMatches(p, k)),
    );
    return state.copyWith.live(watched: watched, values: values);
  }
}
