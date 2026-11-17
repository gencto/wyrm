import '../../app_state.dart';
import '../../common/action.dart';
import 'load_trend_extremes_action.dart';
import 'retrieve_series_action.dart';

/// The trend's series read again ([RetrieveSeriesAction]), then their min
/// and max ([LoadTrendExtremesAction]) once the series are in the state:
/// two steps of one read, each with its own state, in order. It changes no
/// state itself (`null`).
class ReadTrendSeriesAction extends Action {
  @override
  Future<AppState?> reduce() async {
    final read = await dispatchAndWait(RetrieveSeriesAction());
    if (read.isCompletedOk && historian.points.isNotEmpty) {
      await dispatchAndWait(LoadTrendExtremesAction(detail: false));
    }
    return null;
  }
}
