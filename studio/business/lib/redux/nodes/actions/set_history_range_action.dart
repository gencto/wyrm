import '../../app_state.dart';
import '../../common/action.dart';

class SetHistoryRangeAction extends Action {
  SetHistoryRangeAction(this.historyRange);

  final String historyRange;

  @override
  AppState reduce() => state.copyWith.nodes(historyRange: historyRange);
}
