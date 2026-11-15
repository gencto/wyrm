import 'package:models/links_tab.dart';
import 'package:models/update_result.dart';

import '../../app_state.dart';
import '../../common/action.dart';
import '../../quarantine/actions/set_selected_entry_action.dart';
import '../../updates/actions/open_update_action.dart';
import 'set_selected_link_action.dart';

/// A row of Links tapped, by the tab on screen: a connection of
/// Quarantine is selected; a row of Updates opens its package's update
/// sheet (following an update the broker checks); a link of the other
/// tabs is selected.
class OpenLinksRowAction extends Action {
  OpenLinksRowAction(this.id);

  final String id;

  @override
  AppState? reduce() {
    switch (links.tab) {
      case LinksTab.quarantine:
        dispatchSync(SetSelectedEntryAction(id));
      case LinksTab.updates:
        final p = switch (links.table[id]) {
          final l? => packageRunBy(l),
          null => null,
        };
        if (p != null) {
          dispatchSync(
            OpenUpdateAction(
              p.name,
              follow: p.lastUpdate?.result == UpdateResult.checking,
            ),
          );
        }
      case LinksTab.local || LinksTab.remote:
        dispatchSync(SetSelectedLinkAction(id));
    }
    return null;
  }
}
