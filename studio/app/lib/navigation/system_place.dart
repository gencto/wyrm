import 'package:async_redux/async_redux.dart';
import 'package:auto_route/auto_route.dart';
import 'package:business/redux/app_state.dart';
import 'package:models/attention_item.dart';
import 'package:models/attention_kind.dart';
import 'package:models/link_mode.dart';
import 'package:models/links_tab.dart';
import 'package:models/system_tab.dart';

import 'app_router.dart';

/// Where a link of System leads (specs/system.md): another workspace,
/// opened at what the link names, or System's own Availability tab.
enum SystemPlace {
  /// Links › Local.
  links,

  /// Links › Quarantine.
  quarantine,
  sites,
  history,
  access,

  /// Access › Audit.
  audit,

  /// The design system's gallery.
  gallery,

  /// System › Availability.
  availability,
}

/// Opens [place]: the tab of the workspace it names is set, then the
/// workspace is shown. One state for the tab, then the route; nothing
/// else is drawn in between.
class GoSystemPlaceAction extends ReduxAction<AppState> {
  GoSystemPlaceAction(this.place);

  final SystemPlace place;

  @override
  AppState? reduce() => switch (place) {
    SystemPlace.links => state.copyWith.links(tab: LinksTab.local),
    SystemPlace.quarantine => state.copyWith.links(tab: LinksTab.quarantine),
    SystemPlace.audit => state.copyWith.access(tab: 'audit'),
    SystemPlace.availability => state.copyWith.system(
      tab: SystemTab.availability,
    ),
    SystemPlace.sites ||
    SystemPlace.history ||
    SystemPlace.access ||
    SystemPlace.gallery => null,
  };

  @override
  void after() {
    super.after();
    if (_route(place) case final r?) {
      _go(r, push: place == SystemPlace.gallery);
    }
  }

  static PageRouteInfo? _route(SystemPlace p) => switch (p) {
    SystemPlace.links || SystemPlace.quarantine => const LinksRoute(),
    SystemPlace.sites => const SitesRoute(),
    SystemPlace.history => const HistoryRoute(),
    SystemPlace.access || SystemPlace.audit => const AccessRoute(),
    SystemPlace.gallery => const GalleryRoute(),
    SystemPlace.availability => null,
  };
}

/// Opens what a card of System's attention panel is about ([item]): the
/// failed link in Links (Local, or Remote for an external one), the
/// quarantine entry, the broker waiting in Sites, Audit for the ACL
/// counter, Availability for the standby. One state with the selection,
/// then the route.
class OpenAttentionAction extends ReduxAction<AppState> {
  OpenAttentionAction(this.item);

  final AttentionItem item;

  @override
  AppState reduce() {
    final what = item.subject;
    return switch (item.kind) {
      AttentionKind.standbyBehind ||
      AttentionKind.noStandby => state.copyWith.system(
        tab: SystemTab.availability,
      ),
      AttentionKind.linkFailed => state.copyWith.links(
        tab: state.links.table[what]?.mode == LinkMode.external
            ? LinksTab.remote
            : LinksTab.local,
        selectedLink: what,
      ),
      AttentionKind.quarantine => state.copyWith(
        links: state.links.copyWith(tab: LinksTab.quarantine),
        quarantine: state.quarantine.copyWith(selectedEntry: what),
      ),
      AttentionKind.brokerWaiting => state.copyWith.peers(
        selectedPeer: 'waiting:$what',
      ),
      AttentionKind.aclGrown => state.copyWith.access(tab: 'audit'),
    };
  }

  @override
  void after() {
    super.after();
    switch (item.kind) {
      case AttentionKind.standbyBehind || AttentionKind.noStandby:
        break;
      case AttentionKind.linkFailed || AttentionKind.quarantine:
        _go(const LinksRoute());
      case AttentionKind.brokerWaiting:
        _go(const SitesRoute());
      case AttentionKind.aclGrown:
        _go(const AccessRoute());
    }
  }
}

/// Shows [route]: a workspace of the shell (its tab), or a page pushed
/// over it.
void _go(PageRouteInfo route, {bool push = false}) {
  if (push) {
    appRouter.push(route).ignore();
  } else {
    appRouter.navigate(route).ignore();
  }
}
