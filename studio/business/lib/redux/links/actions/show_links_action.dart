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
/// It is marked shown, so `ReloadShownAction` reads it again after a site
/// switch or a reconnect.
///
/// Rebuilds, decided: the mark and the watch change nothing Links draws
/// before the values come (`notify: false`); each read notifies when its
/// own slice changes. This action changes no state itself (`null`).
class ShowLinksAction extends Action {
  @override
  Future<AppState?> reduce() async {
    dispatchSync(_Shown(true), notify: false);
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

/// Links is on screen ([shown]) or not.
class _Shown extends Action {
  _Shown(this.shown);

  final bool shown;

  @override
  AppState? reduce() =>
      state.links.shown == shown ? null : state.copyWith.links(shown: shown);
}
