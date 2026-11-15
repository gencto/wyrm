import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import 'package:models/trend_range.dart';

import '../../app_state.dart';
import '../../common/action.dart';

/// The trend's range (an hour, a day, a week, 30 days): what the brush
/// shows. The window goes back to the whole range, and a read in flight
/// for the old one is superseded (`trendGen`).
class SetRangeAction extends Action {
  SetRangeAction(this.range);

  final TrendRange range;

  @override
  AppState reduce() => state.copyWith.historian(
    range: range,
    window: null,
    detail: null,
    low: const IMapConst({}),
    high: const IMapConst({}),
    trendGen: historian.trendGen + 1,
  );
}
