import '../../app_state.dart';
import '../../common/action.dart';

/// Where the user left the desktop window and how large, in logical
/// pixels; kept across launches by the persistor. A maximized or full
/// screen window does not report here, so the stored frame is the one to
/// restore to.
class SetWindowBoundsAction extends Action {
  SetWindowBoundsAction({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final double left;
  final double top;
  final double width;
  final double height;

  @override
  AppState? reduce() {
    final usable =
        left.isFinite &&
        top.isFinite &&
        width.isFinite &&
        height.isFinite &&
        width > 0 &&
        height > 0;
    if (!usable ||
        (window.left == left &&
            window.top == top &&
            window.width == width &&
            window.height == height)) {
      return null;
    }
    return state.copyWith.window(
      left: left,
      top: top,
      width: width,
      height: height,
    );
  }
}
