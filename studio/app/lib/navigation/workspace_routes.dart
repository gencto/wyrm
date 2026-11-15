import 'package:auto_route/auto_route.dart';
import 'package:models/workspace.dart';

import 'app_router.dart';

/// The route of each workspace.
PageRouteInfo routeOf(Workspace w) => switch (w) {
  Workspace.explorer => const ExplorerRoute(),
  Workspace.links => const LinksRoute(),
  Workspace.flows => const FlowsRoute(),
  Workspace.history => const HistoryRoute(),
  Workspace.access => const AccessRoute(),
  Workspace.sites => const SitesRoute(),
  Workspace.assistant => const AssistantRoute(),
  Workspace.system => const SystemRoute(),
};

/// The eight workspaces' routes in rail order (docs/studio.md §7.1): made
/// from [Workspace], so a tab's index is its workspace's, as
/// `GoAction.workspace` reads it.
final List<PageRouteInfo> workspaceRoutes = [
  for (final w in Workspace.values) routeOf(w),
];
