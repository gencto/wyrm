import '../../../wyrm/trend_window.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import 'read_trend_window_action.dart';
import 'set_trend_window_action.dart';

/// The window [start]…[end] (µs) chosen on History's trend: kept against
/// the trend's range as the store keeps a window ([trendWindow]: the whole
/// range is none, a window to the range's end follows now), shown at once,
/// then read finer ([ReadTrendWindowAction]). Reset zoom is
/// [ZoomHistoryAction.reset]: no window. It changes no state itself.
class ZoomHistoryAction extends Action {
  ZoomHistoryAction(int this.start, int this.end);

  /// Reset zoom: the whole range again.
  ZoomHistoryAction.reset() : start = null, end = null;

  final int? start;
  final int? end;

  @override
  Future<AppState?> reduce() async {
    final range = historian.trendSpan;
    dispatchSync(
      SetTrendWindowAction(switch ((start, end)) {
        (final a?, final b?) => trendWindow(a, b, range.start, range.end),
        _ => null,
      }),
    );
    await dispatchAndWait(ReadTrendWindowAction());
    return null;
  }
}
