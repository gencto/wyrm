import 'package:async_redux/async_redux.dart';
import 'package:auto_route/auto_route.dart';
import 'package:business/redux/app_state.dart';

import 'go_action.dart';

/// Runs [steps] (synchronous business actions: close the drawer, select a
/// node, open its trend), then goes to [route]: one intent, one dispatch
/// (studio-rules §9). `business` cannot navigate, so the step that follows
/// lives here, beside [GoAction].
///
/// The steps are one change on screen: only the last one notifies. It
/// changes no state itself (`null`); the route change is the router's.
class GoAfterAction extends ReduxAction<AppState> {
  GoAfterAction(this.route, this.steps);

  final PageRouteInfo route;
  final List<ReduxAction<AppState>> steps;

  @override
  AppState? reduce() {
    for (final (i, a) in steps.indexed) {
      dispatchSync(a, notify: i == steps.length - 1);
    }
    dispatchSync(GoAction.navigate(route));
    return null;
  }
}
