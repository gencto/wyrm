import 'package:models/history_range.dart';

import '../../app_state.dart';
import '../../common/action.dart';
import 'retrieve_history_action.dart';

/// A history range is picked: the whole range shows, and the point's
/// history is read over it.
class PickHistoryRangeAction extends Action {
  PickHistoryRangeAction(this.range);

  final HistoryRange range;

  @override
  AppState? reduce() {
    // the read starts with its own wait; the range shows now
    dispatchAll([
      if (nodes.point case final p?) RetrieveHistoryAction(p, range: range),
    ]);
    return state.copyWith.nodes(historyRange: range, historyWindow: null);
  }
}
