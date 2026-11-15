import 'package:models/system_tab.dart';

import '../../app_state.dart';
import '../../backups/actions/retrieve_backups_action.dart';
import '../../common/action.dart';
import '../../links/actions/retrieve_links_action.dart';
import '../../live/actions/watch_keys_action.dart';
import '../../peers/actions/retrieve_peers_action.dart';
import '../../quarantine/actions/retrieve_quarantine_action.dart';
import 'retrieve_profiles_action.dart';
import 'retrieve_sys_about_action.dart';
import 'retrieve_system_log_action.dart';
import 'set_shown_action.dart';

/// System comes on screen (its workspace tab is the active one): it is
/// marked shown, its `sys` keys are watched (ADR 0037 rule 5), and what it
/// shows is read, in parallel: the descriptions and units of `sys`, the
/// device profiles, the backups, the quarantine, the log on the Log tab,
/// the links, and the peers when none are held.
///
/// Rebuilds, decided: the mark and the watch change nothing System draws
/// before the values come (`notify: false`); each read notifies when its
/// own slice changes. This action changes no state itself (`null`).
class ShowSystemAction extends Action {
  @override
  Future<AppState?> reduce() async {
    dispatchSync(SetShownAction(true), notify: false);
    dispatchSync(WatchKeysAction(systemKeys(site.root)), notify: false);
    await dispatchAndWaitAll([
      RetrieveSysAboutAction(),
      RetrieveProfilesAction(),
      RetrieveBackupsAction(quiet: true),
      RetrieveQuarantineAction(),
      if (system.tab == SystemTab.log && sysConfigReason == null)
        RetrieveSystemLogAction(),
      RetrieveLinksAction(quiet: true),
    ]);
    if (peers.table.isEmpty) {
      await dispatchAndWait(RetrievePeersAction());
    }
    return null;
  }
}

/// The keys System watches while shown: every value of `sys`, the state of
/// each link, the historian's size and the values of the kept backups
/// (ADR 0048 §3.4).
List<String> systemKeys(String? root) => [
  '$root/sys/*',
  '$root/sys/links/*/state',
  '$root/sys/history/database_size',
  '$root/sys/backups/*/*',
];
