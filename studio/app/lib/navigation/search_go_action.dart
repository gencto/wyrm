import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/site/actions/view_site_action.dart';
import 'package:ui/shell/studio_frame.dart';

import '../mappers/shell_mappers.dart';
import 'explore_action.dart';
import 'go_action.dart';

/// Goes where the search palette's [pick] says: a workspace of the rail,
/// a site to view, or a node shown in Explorer. One intent, one dispatch.
class SearchGoAction extends ReduxAction<AppState> {
  SearchGoAction(this.pick);

  final SearchPick pick;

  @override
  Future<AppState?> reduce() async {
    await dispatchAndWait(switch (pick) {
      PickWorkspace(:final tab) => GoAction.workspace(tab.workspace),
      PickSite(:final site) => ViewSiteAction(site),
      PickKey(:final key) => ExploreAction(key),
    });
    return null;
  }
}
