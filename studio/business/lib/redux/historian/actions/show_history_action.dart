import '../../app_state.dart';
import '../../common/action.dart';
import 'follow_history_action.dart';
import 'read_trend_series_action.dart';
import 'read_trend_window_action.dart';

/// History comes on screen (its workspace tab is the active one): it
/// follows `sys/history` and the picked points, and the picked points'
/// series are read again, with the window when one is open.
///
/// Rebuilds, decided: following changes nothing History draws before the
/// values come (`notify: false`); each read notifies for what it changes.
/// This action changes no state itself (`null`).
class ShowHistoryAction extends Action {
  @override
  Future<AppState?> reduce() async {
    dispatchSync(FollowHistoryAction(show: true), notify: false);
    if (historian.points.isNotEmpty) {
      await dispatchAndWaitAll([
        ReadTrendSeriesAction(),
        if (historian.window != null) ReadTrendWindowAction(),
      ]);
    }
    return null;
  }
}
