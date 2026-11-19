import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/common/action.dart';
import 'package:business/redux/login/actions/open_tree_action.dart';
import 'package:models/unlock_stage.dart';

import 'app_router.dart';
import 'go_action.dart';

/// Runs [inner] (a log-in, an unlock, an answer to the offer of a device
/// key), then opens Studio when it left a session and nothing more to ask
/// on the page: the welcome stays until the first list of the tree has
/// arrived (`OpenTreeAction`), then the route goes to Studio (login.md §5,
/// unlock-discover.md §2). One intent, one dispatch (studio-rules §9);
/// `business` cannot navigate, so the step after a business action lives
/// here, beside [GoAction].
///
/// It changes no state itself (`null`): [inner] and the preload notify for
/// what they change, and the route change is the router's.
class EnterStudioAction extends Action {
  EnterStudioAction(this.inner);

  final ReduxAction<AppState> inner;

  @override
  Future<AppState?> reduce() async {
    await dispatchAndWait(inner);
    // A failed log-in or unlock left no session; the offer waits for the
    // person.
    if (state.session.token == null ||
        state.device.stage == UnlockStage.offer) {
      return null;
    }
    await dispatchAndWait(OpenTreeAction());
    // The auth guard is re-run by the token's listenable, but auto_route
    // 11 does not redirect away from a resolved route on it: go there.
    dispatchSync(GoAction.replace(const StudioRoute()));
    return null;
  }
}
