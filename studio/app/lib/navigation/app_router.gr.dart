// dart format width=80
// GENERATED CODE - DO NOT MODIFY BY HAND

// **************************************************************************
// AutoRouterGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

part of 'app_router.dart';

/// generated route for
/// [AccessPageConnector]
class AccessRoute extends PageRouteInfo<void> {
  const AccessRoute({List<PageRouteInfo>? children})
    : super(AccessRoute.name, initialChildren: children);

  static const String name = 'AccessRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const AccessPageConnector();
    },
  );
}

/// generated route for
/// [AssistantPageConnector]
class AssistantRoute extends PageRouteInfo<void> {
  const AssistantRoute({List<PageRouteInfo>? children})
    : super(AssistantRoute.name, initialChildren: children);

  static const String name = 'AssistantRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const AssistantPageConnector();
    },
  );
}

/// generated route for
/// [ExplorerPageConnector]
class ExplorerRoute extends PageRouteInfo<void> {
  const ExplorerRoute({List<PageRouteInfo>? children})
    : super(ExplorerRoute.name, initialChildren: children);

  static const String name = 'ExplorerRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const ExplorerPageConnector();
    },
  );
}

/// generated route for
/// [FlowEditorPageConnector]
class FlowEditorRoute extends PageRouteInfo<FlowEditorRouteArgs> {
  FlowEditorRoute({required String id, Key? key, List<PageRouteInfo>? children})
    : super(
        FlowEditorRoute.name,
        args: FlowEditorRouteArgs(id: id, key: key),
        initialChildren: children,
      );

  static const String name = 'FlowEditorRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<FlowEditorRouteArgs>();
      return FlowEditorPageConnector(id: args.id, key: args.key);
    },
  );
}

class FlowEditorRouteArgs {
  const FlowEditorRouteArgs({required this.id, this.key});

  final String id;

  final Key? key;

  @override
  String toString() {
    return 'FlowEditorRouteArgs{id: $id, key: $key}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! FlowEditorRouteArgs) return false;
    return id == other.id && key == other.key;
  }

  @override
  int get hashCode => id.hashCode ^ key.hashCode;
}

/// generated route for
/// [FlowsPageConnector]
class FlowsRoute extends PageRouteInfo<void> {
  const FlowsRoute({List<PageRouteInfo>? children})
    : super(FlowsRoute.name, initialChildren: children);

  static const String name = 'FlowsRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const FlowsPageConnector();
    },
  );
}

/// generated route for
/// [GalleryPageConnector]
class GalleryRoute extends PageRouteInfo<void> {
  const GalleryRoute({List<PageRouteInfo>? children})
    : super(GalleryRoute.name, initialChildren: children);

  static const String name = 'GalleryRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const GalleryPageConnector();
    },
  );
}

/// generated route for
/// [HistoryPageConnector]
class HistoryRoute extends PageRouteInfo<void> {
  const HistoryRoute({List<PageRouteInfo>? children})
    : super(HistoryRoute.name, initialChildren: children);

  static const String name = 'HistoryRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const HistoryPageConnector();
    },
  );
}

/// generated route for
/// [LinkInstallPageConnector]
class LinkInstallRoute extends PageRouteInfo<void> {
  const LinkInstallRoute({List<PageRouteInfo>? children})
    : super(LinkInstallRoute.name, initialChildren: children);

  static const String name = 'LinkInstallRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const LinkInstallPageConnector();
    },
  );
}

/// generated route for
/// [LinksPageConnector]
class LinksRoute extends PageRouteInfo<void> {
  const LinksRoute({List<PageRouteInfo>? children})
    : super(LinksRoute.name, initialChildren: children);

  static const String name = 'LinksRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const LinksPageConnector();
    },
  );
}

/// generated route for
/// [LogInPageConnector]
class LogInRoute extends PageRouteInfo<void> {
  const LogInRoute({List<PageRouteInfo>? children})
    : super(LogInRoute.name, initialChildren: children);

  static const String name = 'LogInRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const LogInPageConnector();
    },
  );
}

/// generated route for
/// [SitesPageConnector]
class SitesRoute extends PageRouteInfo<void> {
  const SitesRoute({List<PageRouteInfo>? children})
    : super(SitesRoute.name, initialChildren: children);

  static const String name = 'SitesRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const SitesPageConnector();
    },
  );
}

/// generated route for
/// [SplashPageConnector]
class SplashRoute extends PageRouteInfo<void> {
  const SplashRoute({List<PageRouteInfo>? children})
    : super(SplashRoute.name, initialChildren: children);

  static const String name = 'SplashRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const SplashPageConnector();
    },
  );
}

/// generated route for
/// [StudioPageConnector]
class StudioRoute extends PageRouteInfo<void> {
  const StudioRoute({List<PageRouteInfo>? children})
    : super(StudioRoute.name, initialChildren: children);

  static const String name = 'StudioRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const StudioPageConnector();
    },
  );
}

/// generated route for
/// [SystemPageConnector]
class SystemRoute extends PageRouteInfo<void> {
  const SystemRoute({List<PageRouteInfo>? children})
    : super(SystemRoute.name, initialChildren: children);

  static const String name = 'SystemRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const SystemPageConnector();
    },
  );
}
