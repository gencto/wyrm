import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/live_set.dart';

import '../../app_state.dart';
import '../../common/action.dart';
import '../../live/actions/follow_action.dart';

/// Keeps History live while its tab is shown (`historian.follow`): the
/// live lists of `sys/history` (groups) and of the selected group
/// (watches), the values `sys/history/*` (rows written, size, oldest day …)
/// and `sys/history/*/*` (each group's settings), and the `~val` of the
/// picked points, which extend their trend (`AppendSamplesAction`).
///
/// [show] true starts following, false stops it; null follows again what
/// the state holds now (another group, other points, another site), and
/// does nothing while the tab is hidden.
class FollowHistoryAction extends Action {
  FollowHistoryAction({this.show});

  final bool? show;

  @override
  AppState? reduce() {
    final before = historian.follow;
    final on = show ?? before != null;
    final root = site.root;
    final LiveSet? after;
    if (!on) {
      after = null;
    } else if (root == null) {
      after = const LiveSet();
    } else {
      final base = '$root/sys/history';
      final group = historian.selected;
      after = LiveSet(
        values: ['$base/*', '$base/*/*', ...historian.points].lock,
        lists: [base, if (group != null) '$base/$group'].lock,
      );
    }
    if (after == before) {
      return null;
    }
    dispatchSync(FollowAction(before, after));
    return state.copyWith.historian(follow: after);
  }
}
