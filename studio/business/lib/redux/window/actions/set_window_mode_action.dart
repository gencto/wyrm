import '../../app_state.dart';
import '../../common/action.dart';

/// What the desktop window reports about itself: maximized (the restore
/// icon of the window buttons) and full screen (no room is kept for the
/// native buttons then). Dispatched by the app's window listener.
class SetWindowModeAction extends Action {
  SetWindowModeAction({this.maximized, this.fullScreen});

  /// Null leaves the value as it is.
  final bool? maximized;
  final bool? fullScreen;

  @override
  AppState? reduce() {
    final m = maximized ?? window.maximized;
    final f = fullScreen ?? window.fullScreen;
    if (m == window.maximized && f == window.fullScreen) {
      return null;
    }
    return state.copyWith.window(maximized: m, fullScreen: f);
  }
}
