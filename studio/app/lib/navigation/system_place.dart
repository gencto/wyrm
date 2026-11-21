import 'package:auto_route/auto_route.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/common/action.dart';
import 'package:models/access_tab.dart';
import 'package:models/attention_item.dart';
import 'package:models/link_mode.dart';
import 'package:models/links_tab.dart';
import 'package:models/site_node.dart';
import 'package:models/site_pick.dart';
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
class GoSystemPlaceAction extends Action {
  GoSystemPlaceAction(this.place);

  final SystemPlace place;

  @override
  AppState? reduce() => switch (place) {
    SystemPlace.links => state.copyWith.links(tab: LinksTab.local),
    SystemPlace.quarantine => state.copyWith.links(tab: LinksTab.quarantine),
    SystemPlace.audit => state.copyWith.access(tab: AccessTab.audit),
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
class OpenAttentionAction extends Action {
  OpenAttentionAction(this.item);

  final AttentionItem item;

  @override
  AppState reduce() => switch (item) {
    AttentionStandbyBehind() || AttentionNoStandby() => state.copyWith.system(
      tab: SystemTab.availability,
    ),
    AttentionLinkFailed(:final link) => state.copyWith.links(
      tab: state.links.table[link]?.mode == LinkMode.external
          ? LinksTab.remote
          : LinksTab.local,
      selectedLink: link,
    ),
    AttentionQuarantine(:final node) ||
    AttentionWaitingNotRead(:final node) => state.copyWith(
      links: state.links.copyWith(tab: LinksTab.quarantine),
      quarantine: state.quarantine.copyWith(selectedEntry: node),
    ),
    AttentionBrokerWaiting(:final node) => state.copyWith.peers(
      selectedPeer: SitePick(SiteNode.waiting, node),
    ),
    AttentionAclGrown() => state.copyWith.access(tab: AccessTab.audit),
  };

  @override
  void after() {
    super.after();
    switch (item) {
      case AttentionStandbyBehind() || AttentionNoStandby():
        break;
      case AttentionLinkFailed() ||
          AttentionQuarantine() ||
          AttentionWaitingNotRead():
        _go(const LinksRoute());
      case AttentionBrokerWaiting():
        _go(const SitesRoute());
      case AttentionAclGrown():
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
