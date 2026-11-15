import '../../../wyrm/history_trend.dart';
import '../../../wyrm/trend_window.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import 'set_trend_window_action.dart';

/// The window [start]…[end] (µs) chosen on History's trend: kept against
/// the trend's range as the store keeps a window ([trendWindow]: the whole
/// range is none, a window to the range's end follows now) and read finer
/// by [SetTrendWindowAction]. Changes no state itself.
class ZoomHistoryAction extends Action {
  ZoomHistoryAction(this.start, this.end);

  final int start;
  final int end;

  @override
  AppState? reduce() {
    final range = historyRange;
    dispatchSync(
      SetTrendWindowAction(trendWindow(start, end, range.start, range.end)),
    );
    return null;
  }
}
