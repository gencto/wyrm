import '../../app_state.dart';
import '../../common/action.dart';
import '../../nodes/actions/retrieve_history_action.dart';
import 'retrieve_timeline_audit_action.dart';

/// The drawer's mini timeline: the history of its point (shared with
/// Explorer › History, the same point) and its audit marks, unless they
/// were read for it already. The two reads run side by side, each with its
/// own wait; this action owns them.
class ReadTimelineAction extends Action {
  @override
  Future<AppState?> reduce() async {
    final point = timelinePoint;
    if (point == null) {
      return null;
    }
    await dispatchAndWaitAll([
      if (nodes.historyKey != point) RetrieveHistoryAction(point),
      if (assistant.timelineKey != point) RetrieveTimelineAuditAction(point),
    ]);
    return null;
  }
}
