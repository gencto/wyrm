import 'package:async_redux/async_redux.dart';
import 'package:auto_route/auto_route.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/common/action.dart';

import 'go_action.dart';

/// Runs [steps] (business actions: close the drawer, select a node, open
/// its trend), then goes to [route]: one intent, one dispatch (studio-rules
/// §9). `business` cannot navigate, so the step that follows lives here,
/// beside [GoAction].
///
/// The steps start in order and show their state at once (a selection
/// shows before its reads); the route changes then, and this action ends
/// when the steps' reads have answered. Only the last step notifies. It
/// changes no state itself (`null`); the route change is the router's.
class GoAfterAction extends Action {
  GoAfterAction(this.route, this.steps);

  final PageRouteInfo route;
  final List<ReduxAction<AppState>> steps;

  @override
  Future<AppState?> reduce() async {
    final running = [
      for (final (i, a) in steps.indexed)
        dispatchAndWait(a, notify: i == steps.length - 1),
    ];
    dispatchSync(GoAction.navigate(route));
    await Future.wait(running);
    return null;
  }
}
