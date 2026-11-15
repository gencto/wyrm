import 'package:models/history_range.dart';

import '../../app_state.dart';
import '../../common/action.dart';
import 'retrieve_history_action.dart';
import 'set_history_range_action.dart';

/// A history range is picked: the whole range shows at once, then the
/// point's history is read over it (this action ends when it answers).
class PickHistoryRangeAction extends Action {
  PickHistoryRangeAction(this.range);

  final HistoryRange range;

  @override
  Future<AppState?> reduce() async {
    dispatchSync(SetHistoryRangeAction(range));
    if (nodes.point case final p?) {
      await dispatchAndWait(RetrieveHistoryAction(p));
    }
    return null;
  }
}
