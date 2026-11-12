import 'package:models/hist_window.dart';

import '../../app_state.dart';
import '../../common/action.dart';

/// The window of a point's trend in the Explorer (spec trend.md §4): it
/// zooms on the rows already read for the range (≤ 2000 raw rows), so it
/// reads nothing. Null is the whole range.
class SetHistoryWindowAction extends Action {
  SetHistoryWindowAction(this.next);

  final HistWindow? next;

  @override
  AppState? reduce() => next == nodes.historyWindow
      ? null
      : state.copyWith.nodes(historyWindow: next);
}
