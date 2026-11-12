import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/live_set.dart';

import '../../app_state.dart';
import '../../common/action.dart';
import '../../live/actions/follow_action.dart';

/// Keeps Flows live while its tab is shown (`flows.follow`): the live list
/// of `dataflows` (`ApplyFlowsListAction`) and the `~val` of
/// `dataflows/*` (`ApplyFlowValuesAction`).
///
/// [show] true starts following, false stops it; null follows again for
/// the site on screen, and does nothing while the tab is hidden.
class FollowFlowsAction extends Action {
  FollowFlowsAction({this.show});

  final bool? show;

  @override
  AppState? reduce() {
    final before = flows.follow;
    final on = show ?? before != null;
    final root = site.root;
    final LiveSet? after;
    if (!on) {
      after = null;
    } else if (root == null) {
      after = const LiveSet();
    } else {
      final base = '$root/dataflows';
      after = LiveSet(values: ['$base/*'].lock, lists: [base].lock);
    }
    if (after == before) {
      return null;
    }
    dispatchSync(FollowAction(before, after));
    return state.copyWith.flows(follow: after);
  }
}
