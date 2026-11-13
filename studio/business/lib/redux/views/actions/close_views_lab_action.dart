import '../../app_state.dart';
import '../../common/action.dart';

/// The lab is left: every subscription and list of the view is closed and
/// its values are dropped.
class CloseViewsLabAction extends Action {
  @override
  AppState? reduce() {
    deps.viewBridge.close();
    return state.copyWith.views(
      open: false,
      data: const .empty(),
      keys: const .empty(),
      children: const .empty(),
    );
  }
}
