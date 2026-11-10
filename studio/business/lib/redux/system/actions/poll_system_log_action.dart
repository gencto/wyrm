import '../../app_state.dart';
import '../../common/action.dart';
import 'retrieve_system_log_action.dart';

/// The Log tab's `every 5 s`: the same read as `RetrieveSystemLogAction`,
/// but not in `Wait`, so a poll is not a refresh of the workspace (no sweep
/// bar every five seconds, docs/studio.md §6.7). It does nothing while the
/// tab is hidden, auto-refresh is off, or a read is already in flight.
class PollSystemLogAction extends Action {
  @override
  Future<AppState?> reduce() async {
    if (!system.shown || !system.auto || system.tab != 'log') {
      return null;
    }
    if (system.isWaiting) {
      return null;
    }
    return readSystemLog(this);
  }
}
