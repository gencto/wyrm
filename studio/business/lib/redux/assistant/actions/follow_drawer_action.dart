import '../../app_state.dart';
import '../../common/action.dart';
import 'read_timeline_action.dart';
import 'watch_drawer_findings_action.dart';

/// What the drawer shows moved (its task's findings, Explorer's point):
/// the finding nodes it watches follow at once, and the history and audit
/// of the timeline's point are read when they are not yet. Each part
/// changes nothing when nothing moved for it.
class FollowDrawerAction extends Action {
  @override
  Future<AppState?> reduce() async {
    dispatchSync(WatchDrawerFindingsAction());
    await dispatchAndWait(ReadTimelineAction());
    return null;
  }
}
