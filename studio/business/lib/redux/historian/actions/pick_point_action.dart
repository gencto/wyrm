import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import '../../app_state.dart';
import '../../common/action.dart';
import 'follow_history_action.dart';

/// Picks the recorded key [key] of the selected group for the trend. A
/// plain pick shows that point alone (a second pick of it clears it);
/// [add] (⌘/Ctrl-click) adds it to the points on the trend, or takes it
/// off when it is there, up to [max] at once (the oldest goes).
class PickPointAction extends Action {
  PickPointAction(this.key, {this.add = false});

  final String key;
  final bool add;

  /// Points on one trend at most.
  static const max = 3;

  @override
  AppState? reduce() {
    final now = historian.points;
    final IList<String> next;
    if (!add) {
      next = now.length == 1 && now.first == key
          ? const IListConst([])
          : [key].lock;
    } else if (now.contains(key)) {
      next = now.remove(key);
    } else {
      final grown = now.add(key);
      next = grown.length > max ? grown.removeAt(0) : grown;
    }
    return state.copyWith.historian(
      points: next,
      series: {
        for (final e in historian.series.entries)
          if (next.contains(e.key)) e.key: e.value,
      }.lock,
    );
  }

  /// While History is shown, its subscriptions follow the new points.
  @override
  void after() {
    super.after();
    dispatchSync(FollowHistoryAction());
  }
}
