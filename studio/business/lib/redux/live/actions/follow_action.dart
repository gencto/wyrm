import 'package:models/live_set.dart';

import '../../app_state.dart';
import '../../common/action.dart';
import 'unwatch_keys_action.dart';
import 'watch_keys_action.dart';

/// A shown screen moves from what it kept live ([from], null when it was
/// hidden) to [to] (null when it hides): the value keys it gains are
/// watched and the ones it drops unwatched (`live.watched` counts readers,
/// so another screen's subscription of the same key stays), and the lists
/// it gains and drops are counted in `live.lists`, which
/// `LiveListsService` follows.
///
/// The screen keeps [to] itself, so a hide or a site switch closes
/// exactly what it opened, whatever `site.root` reads by then.
class FollowAction extends Action {
  FollowAction(this.from, this.to);

  final LiveSet? from;
  final LiveSet? to;

  @override
  AppState? reduce() {
    final was = from ?? const LiveSet();
    final now = to ?? const LiveSet();
    final gainedValues = now.values.where((k) => !was.values.contains(k));
    final lostValues = was.values.where((k) => !now.values.contains(k));
    if (gainedValues.isNotEmpty) {
      dispatchSync(WatchKeysAction(gainedValues.toList()));
    }
    if (lostValues.isNotEmpty) {
      dispatchSync(UnwatchKeysAction(lostValues.toList()));
    }
    var lists = state.live.lists;
    for (final k in now.lists.toSet()) {
      if (!was.lists.contains(k)) {
        lists = lists.add(k, (lists[k] ?? 0) + 1);
      }
    }
    for (final k in was.lists.toSet()) {
      if (!now.lists.contains(k)) {
        final n = lists[k] ?? 0;
        lists = n <= 1 ? lists.remove(k) : lists.add(k, n - 1);
      }
    }
    if (lists == state.live.lists) {
      return null;
    }
    deps.liveLists.sync(lists.keys);
    return state.copyWith.live(lists: lists);
  }
}
