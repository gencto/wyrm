import '../../app_state.dart';
import '../../common/action.dart';

/// The time a screen shows its rows at (`clock.now`), read from
/// `AppDependencies.clock` when a screen that shows times opens and on each
/// of its ticks: a view-model is made of the state alone, so it is equal
/// from one dispatch to the next, and the times it shows move on with the
/// ticks a screen asks for (a device used just now, a gateway seen 3 s ago).
class TickClockAction extends Action {
  @override
  AppState reduce() => state.copyWith.clock(now: deps.clock());
}
