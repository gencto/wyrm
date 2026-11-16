import '../../app_state.dart';
import '../../common/action.dart';
import 'load_trend_extremes_action.dart';
import 'load_trend_window_action.dart';

/// The trend's window read finer ([LoadTrendWindowAction], debounced),
/// then the window's min and max ([LoadTrendExtremesAction]) when it was
/// read in buckets: two steps of one read, each with its own state, in
/// order. A read the debounce dropped reads no extremes. It changes no
/// state itself (`null`).
class ReadTrendWindowAction extends Action {
  @override
  Future<AppState?> reduce() async {
    final read = await dispatchAndWait(LoadTrendWindowAction());
    if (read.isCompletedOk && (historian.detail?.step ?? 'raw') != 'raw') {
      await dispatchAndWait(LoadTrendExtremesAction(detail: true));
    }
    return null;
  }
}
