import 'package:async_redux/async_redux.dart';
import 'package:auto_route/auto_route.dart';
import 'package:business/redux/app_state.dart';
import 'package:models/workspace.dart';

import 'app_router.dart';

/// Navigation as a dispatchable action, so navigation flows through Redux
/// (observable by action observers, testable) instead of connectors poking the
/// router directly. It performs a side effect and changes no state.
///
/// With auto_route the destination is a type-safe generated route
/// (`RegistrationRoute`, `HomeRoute`, …) rather than a string name.
class GoAction extends ReduxAction<AppState> {
  GoAction._(this._navigate);

  factory GoAction.push(PageRouteInfo route) =>
      GoAction._(() => appRouter.push(route));

  /// Replaces the current route (no back to it).
  factory GoAction.replace(PageRouteInfo route) =>
      GoAction._(() => appRouter.replace(route));

  /// Navigates to [route] — pushes it, or updates in place if already present.
  factory GoAction.navigate(PageRouteInfo route) =>
      GoAction._(() => appRouter.navigate(route));

  factory GoAction.pop() => GoAction._(() => appRouter.maybePop());

  /// Shows the workspace [ws] of the rail (the tabs of the Studio page).
  factory GoAction.workspace(Workspace ws) => GoAction._(
    () => appRouter
        .innerRouterOf<TabsRouter>(StudioRoute.name)
        ?.setActiveIndex(ws.index),
  );

  /// Pops every route back to the root of the stack.
  factory GoAction.popUntilRoot() => GoAction._(() => appRouter.popUntilRoot());

  final void Function() _navigate;

  @override
  AppState? reduce() {
    _navigate();
    return null;
  }
}
