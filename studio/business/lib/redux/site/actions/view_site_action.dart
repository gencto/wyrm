import 'dart:async';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import '../../app_state.dart';
import '../../backups/models/backups_state.dart';
import '../../broker_update/models/broker_update_state.dart';
import '../../common/action.dart';
import '../../flows/actions/follow_flows_action.dart';
import '../../historian/actions/follow_history_action.dart';
import '../../historian/models/historian_state.dart';
import '../../links/actions/retrieve_links_action.dart';
import '../../links/models/links_state.dart';
import '../../nodes/models/nodes_state.dart';
import '../../updates/models/updates_state.dart';

/// Shows [target] (a site the switcher offers): every screen's tables are
/// emptied and read again from `wy/<target>`; the tree's lists close, and
/// the lists and values History and Flows follow move to the new site.
class ViewSiteAction extends Action {
  ViewSiteAction(this.target);

  final String target;

  /// The site that was shown, when this run changed it.
  String? _from;

  @override
  AppState? reduce() {
    if (target == site.viewed) {
      return null;
    }
    deps.treeWatch.detachLists();
    _from = site.viewed;
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
      // The update sheet, the backups and the broker update belong to the
      // site that was shown: a package of the same name on the other site
      // is another package, and `sys/backups` there has its own options.
      // A download that runs sees `downloading` cleared and stops.
      updates: const UpdatesState(),
      backups: const BackupsState(),
      brokerUpdate: const BrokerUpdateState(),
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
    if (_from case final from?) {
      dispatchSync(_MoveWatched('wy/$from/', 'wy/$target/'));
    }
    unawaited(dispatchAndWait(RetrieveLinksAction()));
  }
}

/// The keys a shown screen still watches on the site that was left
/// (`sys/links/*/state`, `sys/packages/*/*`, `sys/backups/*/*`, …) move to
/// the new site: the screen stays shown, so nothing would watch them again,
/// and its `onHide` later unwatches the keys of the site it is on then.
/// History and Flows moved their own before this runs.
class _MoveWatched extends Action {
  _MoveWatched(this.from, this.to);

  final String from;
  final String to;

  @override
  AppState? reduce() {
    if (!state.live.watched.keys.any((k) => k.startsWith(from))) {
      return null;
    }
    var watched = const IMapConst<String, int>({}) as IMap<String, int>;
    for (final e in state.live.watched.entries) {
      final key = e.key.startsWith(from)
          ? '$to${e.key.substring(from.length)}'
          : e.key;
      watched = watched.add(key, (watched[key] ?? 0) + e.value);
    }
    deps.liveValues.sync(watched.keys);
    return state.copyWith.live(
      watched: watched,
      values: state.live.values.removeWhere((k, _) => k.startsWith(from)),
    );
  }
}
