import '../../app_state.dart';
import '../../common/action.dart';

/// The range of a point's history in the Explorer (`1h`, `24h`, `7d`); its
/// trend's window goes back to the whole range.
class SetHistoryRangeAction extends Action {
  SetHistoryRangeAction(this.historyRange);

  final String historyRange;

  @override
  AppState reduce() =>
      state.copyWith.nodes(historyRange: historyRange, historyWindow: null);
}
