import '../../app_state.dart';
import '../../common/action.dart';
import '../../live/actions/unwatch_keys_action.dart';

/// Explorer's tab is hidden: the keys it watched are let go.
class HideExplorerAction extends Action {
  @override
  AppState? reduce() {
    final keys = nodes.watching;
    if (keys == null) {
      return null;
    }
    dispatchSync(UnwatchKeysAction(keys), notify: false);
    return state.copyWith.nodes(watching: null);
  }
}
