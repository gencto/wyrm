import 'dart:async';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import '../../app_state.dart';
import '../../common/action.dart';
import '../../flows/actions/follow_flows_action.dart';
import '../../historian/actions/follow_history_action.dart';
import '../../historian/models/historian_state.dart';
import '../../links/actions/retrieve_links_action.dart';
import '../../links/models/links_state.dart';
import '../../nodes/models/nodes_state.dart';

/// Shows [target] (a site the switcher offers): every screen's tables are
/// emptied and read again from `wy/<target>`; the tree's lists close, and
/// the lists and values History and Flows follow move to the new site.
class ViewSiteAction extends Action {
  ViewSiteAction(this.target);

  final String target;

  @override
  AppState? reduce() {
    if (target == site.viewed) {
      return null;
    }
    deps.treeWatch.detachLists();
    return state.copyWith(
      site: state.site.copyWith(current: target == site.name ? null : target),
      nodes: const NodesState(),
      links: LinksState(tab: state.links.tab),
      quarantine: state.quarantine.copyWith(
        table: const IMapConst({}),
        view: const IListConst([]),
        selectedEntry: null,
      ),
      packages: state.packages.copyWith(
        table: const IMapConst({}),
        view: const IListConst([]),
      ),
      // Each site has its own block catalogue and flows. What a shown
      // screen follows (`follow`) is kept: `after` moves it to the new site.
      flows: state.flows.copyWith(
        blockTypes: const IListConst([]),
        table: const IMapConst({}),
        view: const IListConst([]),
        selectedFlow: null,
      ),
      historian: HistorianState(
        range: state.historian.range,
        follow: state.historian.follow,
      ),
    );
  }

  @override
  void after() {
    super.after();
    for (final reload in deps.reloads) {
      reload(store);
    }
    // A shown History or Flows closes the old site's lists and values and
    // opens the new site's; their lists fill them again.
    dispatchSync(FollowHistoryAction());
    dispatchSync(FollowFlowsAction());
    unawaited(dispatchAndWait(RetrieveLinksAction()));
  }
}
