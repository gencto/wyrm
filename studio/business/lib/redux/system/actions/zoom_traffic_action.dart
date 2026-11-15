import '../../../wyrm/trend_window.dart';
import '../../app_state.dart';
import '../../common/action.dart';

/// The traffic trend's window moved to [start]…[end] (µs) on the ring of
/// samples: kept as `system.trafficWindow` (none for the whole ring, an
/// open end while it reaches the newest sample). Nothing before two
/// samples.
class ZoomTrafficAction extends Action {
  ZoomTrafficAction(this.start, this.end);

  final int start;
  final int end;

  @override
  AppState? reduce() {
    final ring = system.samples;
    if (ring.length < 2) {
      return null;
    }
    return state.copyWith.system(
      trafficWindow: trendWindow(
        start,
        end,
        ring.first.time.microsecondsSinceEpoch,
        ring.last.time.microsecondsSinceEpoch,
      ),
    );
  }
}
