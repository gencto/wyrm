import '../../app_state.dart';
import '../../common/action.dart';
import 'retrieve_series_action.dart';

/// History's trend read again after an action of `sys/history` went
/// through (a purge, a watch stopped), when points are picked: the groups,
/// watches and values follow by themselves. Nothing when none is picked.
class RereadTrendAction extends Action {
  @override
  Future<AppState?> reduce() async {
    if (historian.points.isNotEmpty) {
      await dispatchAndWait(RetrieveSeriesAction());
    }
    return null;
  }
}
