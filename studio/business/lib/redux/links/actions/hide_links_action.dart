import '../../app_state.dart';
import '../../common/action.dart';
import '../../live/actions/unwatch_keys_action.dart';

/// Links leaves the screen: its keys are watched no longer. It changes no
/// state Links draws.
class HideLinksAction extends Action {
  @override
  AppState? reduce() {
    dispatchSync(UnwatchKeysAction(linksKeys));
    return null;
  }
}
