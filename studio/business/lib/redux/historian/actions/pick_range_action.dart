import 'package:models/trend_range.dart';

import '../../app_state.dart';
import '../../common/action.dart';
import 'retrieve_series_action.dart';
import 'set_range_action.dart';

/// A range picked on History's trend: one intent. The range shows at once
/// (the tab and the brush, one state); the series are read for it by their
/// own action, which notifies when they come.
class PickRangeAction extends Action {
  PickRangeAction(this.range);

  final TrendRange range;

  @override
  Future<AppState?> reduce() async {
    if (range == historian.range) {
      return null;
    }
    dispatchSync(SetRangeAction(range));
    await dispatchAndWait(RetrieveSeriesAction());
    return null;
  }
}
