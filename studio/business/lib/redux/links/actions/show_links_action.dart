import '../../app_state.dart';
import '../../backups/actions/retrieve_backups_action.dart';
import '../../common/action.dart';
import '../../live/actions/watch_keys_action.dart';
import '../../packages/actions/retrieve_packages_action.dart';
import '../../quarantine/actions/retrieve_quarantine_action.dart';
import 'retrieve_links_action.dart';

/// Links comes on screen (its workspace tab is the active one): its keys
/// are watched (ADR 0037 rule 5) and what it shows is read, in parallel:
/// the links, the quarantine, the packages and whether the broker keeps
/// backups.
///
/// Rebuilds, decided: the watch changes nothing Links draws before the
/// values come (`notify: false`); each read notifies when its own slice
/// changes. This action changes no state itself (`null`).
class ShowLinksAction extends Action {
  @override
  Future<AppState?> reduce() async {
    dispatchSync(WatchKeysAction(linksKeys), notify: false);
    await dispatchAndWaitAll([
      RetrieveLinksAction(),
      RetrieveQuarantineAction(),
      RetrievePackagesAction(),
      RetrieveBackupsAction(quiet: true),
    ]);
    return null;
  }
}
