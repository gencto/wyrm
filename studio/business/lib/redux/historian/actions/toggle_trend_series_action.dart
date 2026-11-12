import '../../app_state.dart';
import '../../common/action.dart';

/// Hides or shows the picked point [key] on the trend (its legend button):
/// gone from the plot, the brush and the tooltip; the Y range follows. It
/// stays picked and read.
class ToggleTrendSeriesAction extends Action {
  ToggleTrendSeriesAction(this.key);

  final String key;

  @override
  AppState reduce() {
    final h = historian.hidden;
    return state.copyWith.historian(
      hidden: h.contains(key) ? h.remove(key) : h.add(key),
    );
  }
}
