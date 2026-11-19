import '../../app_state.dart';
import '../../common/action.dart';
import '../../live/actions/unwatch_keys_action.dart';

/// Links leaves the screen: its keys are watched no longer, and it is no
/// longer marked shown (a reload does not read it again). The mark changes
/// nothing Links draws.
class HideLinksAction extends Action {
  @override
  AppState? reduce() {
    dispatchSync(UnwatchKeysAction(linksKeys));
    return state.links.shown ? state.copyWith.links(shown: false) : null;
  }
}
