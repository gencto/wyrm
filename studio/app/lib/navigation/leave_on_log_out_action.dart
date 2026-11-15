import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';

import 'app_router.dart';
import 'go_action.dart';

/// Runs [inner] to its end, then goes to the log-in page when [inner] ended
/// the session (`Sign out everywhere`, `Log out`, a refused unlock): one
/// intent, one dispatch (studio-rules §9). `business` cannot navigate, so
/// the step that follows a business action lives here, beside [GoAction].
///
/// It changes no state itself (`null`): [inner] notifies for what it
/// changed, and the route change is the router's.
class LeaveOnLogOutAction extends ReduxAction<AppState> {
  LeaveOnLogOutAction(this.inner);

  final ReduxAction<AppState> inner;

  @override
  Future<AppState?> reduce() async {
    await dispatchAndWait(inner);
    if (state.session.token == null) {
      dispatchSync(GoAction.replace(const LogInRoute()));
    }
    return null;
  }
}
