import 'package:models/hist_window.dart';

import '../../app_state.dart';
import '../../common/action.dart';

/// `Follow now` on the traffic trend: the window keeps its width and its
/// end follows the newest sample. Nothing to do while it follows already.
class FollowTrafficAction extends Action {
  @override
  AppState? reduce() => switch (system.trafficWindow) {
    final w? when w.end != null => state.copyWith.system(
      trafficWindow: HistWindow(span: w.span),
    ),
    _ => null,
  };
}
