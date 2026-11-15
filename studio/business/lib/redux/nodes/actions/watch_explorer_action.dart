import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import '../../../wyrm/explorer.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import '../../live/actions/watch_keys_action.dart';

/// Explorer's keys are watched (ADR 0037 rule 5: only keys on screen are
/// subscribed) and kept in `nodes.watching`, in one state.
class WatchExplorerAction extends Action {
  @override
  AppState? reduce() {
    final keys = ExplorerView(state).watchKeys;
    dispatchSync(WatchKeysAction(keys), notify: false);
    return state.copyWith.nodes(watching: keys.lock);
  }
}
