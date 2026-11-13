import 'package:async_redux/async_redux.dart';
import 'package:auto_route/auto_route.dart';
import 'package:business/redux/app_state.dart';
import 'package:material_ui/material_ui.dart';

import '../connectors/access_page_connector.dart';
import '../connectors/assistant_page_connector.dart';
import '../connectors/explorer_page_connector.dart';
import '../connectors/flow_editor_page_connector.dart';
import '../connectors/flows_page_connector.dart';
import '../connectors/gallery_page_connector.dart';
import '../connectors/history_page_connector.dart';
import '../connectors/link_install_page_connector.dart';
import '../connectors/links_page_connector.dart';
import '../connectors/log_in_page_connector.dart';
import '../connectors/sites_page_connector.dart';
import '../connectors/splash_page_connector.dart';
import '../connectors/studio_page_connector.dart';
import '../connectors/system_page_connector.dart';
import '../connectors/views_lab_page_connector.dart';

part 'app_router.gr.dart';

/// The single app router instance. Assigned once by [createAppRouter].
/// Navigation goes through it — directly, or (preferred) via `GoAction`.
late final AppRouter appRouter;

/// Builds the one and only [AppRouter] and stores it in [appRouter]. The store
/// is injected so the auth guard can read the session synchronously.
AppRouter createAppRouter(Store<AppState> store) =>
    appRouter = AppRouter(store);

/// The app router. Route classes (`LogInRoute`, `HomeRoute`, …) are generated
/// into `app_router.gr.dart` from the `@RoutePage()` connectors, so adding a
/// page is: annotate a connector, add one `AutoRoute` line here, run
/// build_runner. The auth gate lives in [_AuthGuard], re-run whenever the
/// logged-in state flips (see `reevaluateListenable` in `run_env.dart`).
@AutoRouterConfig(replaceInRouteName: 'PageConnector|Page,Route')
class AppRouter extends RootStackRouter {
  AppRouter(this._store);

  final Store<AppState> _store;

  @override
  List<AutoRouteGuard> get guards => [_AuthGuard(_store)];

  @override
  List<AutoRoute> get routes => [
    AutoRoute(page: SplashRoute.page, path: '/splash', initial: true),
    AutoRoute(page: LogInRoute.page, path: '/login'),
    AutoRoute(page: GalleryRoute.page, path: '/gallery'),
    AutoRoute(
      page: StudioRoute.page,
      path: '/studio',
      children: [
        AutoRoute(page: ExplorerRoute.page, path: 'explorer'),
        AutoRoute(page: LinksRoute.page, path: 'links'),
        AutoRoute(page: FlowsRoute.page, path: 'flows'),
        AutoRoute(page: HistoryRoute.page, path: 'history'),
        AutoRoute(page: AccessRoute.page, path: 'access'),
        AutoRoute(page: SitesRoute.page, path: 'sites'),
        AutoRoute(page: AssistantRoute.page, path: 'assistant'),
        AutoRoute(page: SystemRoute.page, path: 'system'),
      ],
    ),
    AutoRoute(page: LinkInstallRoute.page, path: '/link-install'),
    AutoRoute(page: FlowEditorRoute.page, path: '/flow-editor/:id'),
    AutoRoute(page: ViewsLabRoute.page, path: '/views-lab'),
  ];
}

/// Auth gate as a global guard — the auto_route analogue of the old go_router
/// `redirect`. Reads the session straight from the store; combined with a
/// `reevaluateListenable` on the session token, it re-runs whenever login
/// state flips, so logging in/out bounces the user to the right area.
class _AuthGuard extends AutoRouteGuard with Selectors {
  const _AuthGuard(this._store);

  final Store<AppState> _store;

  /// The one member the facade asks for — read live, so every run of the
  /// guard sees the store as it is at that moment, not as it was when the
  /// guard was built.
  @override
  AppState get state => _store.state;

  /// Routes reachable while logged out. Everything else requires a session.
  static const Set<String> _authArea = {
    LogInRoute.name,
  };

  @override
  void onNavigation(NavigationResolver resolver, StackRouter router) {
    // Through the selector, not `_store.state.session.token != null`: the
    // facade is where "is there a session" is spelled, and spelling it again
    // here left `SelectSession.isAvailable` with no reader at all.
    final loggedIn = session.isAvailable;
    final name = resolver.routeName;

    // Splash is a pure gate: bounce straight to the right area.
    if (name == SplashRoute.name) {
      resolver.redirectUntil(
        loggedIn ? const StudioRoute() : const LogInRoute(),
        replace: true,
      );
      return;
    }

    final inAuthArea = _authArea.contains(name);
    if (!loggedIn && !inAuthArea) {
      resolver.redirectUntil(const LogInRoute(), replace: true);
      return;
    }
    if (loggedIn && inAuthArea) {
      resolver.redirectUntil(const StudioRoute(), replace: true);
      return;
    }
    resolver.next();
  }
}
