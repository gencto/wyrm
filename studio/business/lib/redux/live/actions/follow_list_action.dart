import '../../app_state.dart';
import '../../common/action.dart';
import '../../flows/actions/apply_flows_list_action.dart';
import '../../flows/actions/retrieve_flow_defs_action.dart';
import '../../historian/actions/apply_history_list_action.dart';
import '../../historian/actions/follow_history_action.dart';
import '../../historian/actions/retrieve_group_watches_action.dart';
import '../../services/live_lists/live_lists_dispatcher.dart';

/// One update of a live list ([change] of [parent]), to the screen whose
/// key it is: `dataflows` to Flows, `sys/history` and its groups to
/// History. The list is shown at once; what it needs read next (a new
/// flow's definition, the watches of a group not listed live) is the next
/// step, awaited here. Each step checks the key against the site on
/// screen, so a late update of the site left changes nothing. It changes
/// no state itself (`null`).
class FollowListAction extends Action {
  FollowListAction(this.parent, this.change);

  final String parent;
  final ListChange change;

  @override
  Future<AppState?> reduce() async {
    if (parent.endsWith('/dataflows')) {
      final list = ApplyFlowsListAction(parent, change);
      dispatchSync(list);
      if (list.unread.isNotEmpty) {
        await dispatchAndWait(RetrieveFlowDefsAction(list.unread));
      }
    } else if (parent.contains('/sys/history')) {
      final list = ApplyHistoryListAction(parent, change);
      dispatchSync(list);
      // The selected group is listed live; the others are read once.
      final read = [
        for (final n in list.unread)
          if (n != historian.selected) n,
      ];
      dispatchSync(FollowHistoryAction());
      if (read.isNotEmpty) {
        await dispatchAndWait(RetrieveGroupWatchesAction(read));
      }
    }
    return null;
  }
}
