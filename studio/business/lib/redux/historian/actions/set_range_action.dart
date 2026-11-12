import '../../app_state.dart';
import '../../common/action.dart';

/// The trend's range (`1h`, `24h`, `7d`, `30d`): what the brush shows. The
/// window goes back to the whole range, and a read in flight for the old
/// one is superseded (`trendGen`).
class SetRangeAction extends Action {
  SetRangeAction(this.range);

  final String range;

  @override
  AppState reduce() => state.copyWith.historian(
    range: range,
    window: null,
    detail: null,
    trendGen: historian.trendGen + 1,
  );
}
