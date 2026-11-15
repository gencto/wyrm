import '../../app_state.dart';
import '../../common/action.dart';
import 'load_trend_window_action.dart';
import 'pick_point_action.dart';
import 'retrieve_series_action.dart';

/// A point row of History was clicked: one intent (studio-rules §9). The
/// pick shows at once ([PickPointAction], a plain click shows [key] alone,
/// [add] toggles it among the trend's points); then the trend's series are
/// read again, and its window too when one is open. Each read is its own
/// action with its own state; this one changes none ([reduce] returns
/// null).
class PickTrendPointAction extends Action {
  PickTrendPointAction(this.key, {this.add = false});

  final String key;
  final bool add;

  @override
  Future<AppState?> reduce() async {
    dispatchSync(PickPointAction(key, add: add));
    await Future.wait([
      dispatchAndWait(RetrieveSeriesAction()),
      if (historian.window != null) dispatchAndWait(LoadTrendWindowAction()),
    ]);
    return null;
  }
}
