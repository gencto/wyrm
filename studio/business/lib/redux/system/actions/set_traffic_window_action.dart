import 'package:models/hist_window.dart';

import '../../app_state.dart';
import '../../common/action.dart';

/// The window of the router traffic trend (spec trend.md §4, live): null
/// is the whole ring (at most an hour); an open end follows now (`Follow
/// now`), a fixed one stays while new samples arrive.
class SetTrafficWindowAction extends Action {
  SetTrafficWindowAction(this.next);

  final HistWindow? next;

  @override
  AppState? reduce() => next == system.trafficWindow
      ? null
      : state.copyWith.system(trafficWindow: next);
}
