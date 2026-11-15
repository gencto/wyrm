import '../../../wyrm/explorer.dart';
import '../../../wyrm/trend_window.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import 'set_history_window_action.dart';

/// The trend's window is moved to [start]…[end] (µs): it zooms on the rows
/// already read for the range, so it reads nothing.
class ZoomHistoryAction extends Action {
  ZoomHistoryAction(this.start, this.end);

  final int start;
  final int end;

  @override
  AppState? reduce() {
    final (rs, re) = ExplorerView(state).historyBounds;
    dispatchSync(SetHistoryWindowAction(trendWindow(start, end, rs, re)));
    return null;
  }
}
