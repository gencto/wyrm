import 'dart:async';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import '../../app_state.dart';
import '../../common/action.dart';
import '../../links/actions/retrieve_links_action.dart';
import '../../links/models/links_state.dart';
import '../../nodes/models/nodes_state.dart';

/// Shows [target] (a site the switcher offers): every screen's tables are
/// emptied and read again from `wy/<target>`; the tree's lists close.
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
    );
  }

  @override
  void after() {
    for (final reload in deps.reloads) {
      reload(store);
    }
    unawaited(dispatchAndWait(RetrieveLinksAction()));
  }
}
