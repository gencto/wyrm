import '../../app_state.dart';
import '../../assistant/actions/load_assistant_action.dart';
import '../../backups/actions/retrieve_backups_action.dart';
import '../../common/action.dart';
import '../../links/actions/retrieve_links_action.dart';
import '../../packages/actions/retrieve_packages_action.dart';
import '../../quarantine/actions/retrieve_quarantine_action.dart';

/// Reads again what a shown screen holds: after the gateway socket is back
/// and after a site switch (`deps.reloads`, docs/studio.md §5.2). One
/// action that owns the reload and awaits its parts in parallel
/// (studio-rules §1, §9), in place of a fire-and-forget dispatch per part.
///
/// Rebuilds, decided: each part notifies when its own slice changes, as it
/// would on its own. This action changes no state (`null`), and its wait is
/// recorded without a notification on either side ([notifyBefore] false,
/// [notifyAfter] false): no screen draws "reloading", so raising the flag
/// must not rebuild every connector. A screen that one day shows it reads
/// `isWaitingForType<ReloadShownAction>()` and turns [notifyBefore] on.
class ReloadShownAction extends Action with WaitingAction {
  @override
  bool get notifyBefore => false;

  @override
  Future<AppState?> reduce() async {
    await dispatchAndWaitAll([
      if (links.view.isNotEmpty) RetrieveLinksAction(),
      if (quarantine.view.isNotEmpty) RetrieveQuarantineAction(),
      if (packages.view.isNotEmpty) RetrievePackagesAction(),
      if (backups.sections.isNotEmpty) RetrieveBackupsAction(quiet: true),
      // the Assistant reads its agent again: after a site switch it is the
      // new site's agent, with its own tasks
      if (assistant.shown) LoadAssistantAction(),
    ]);
    return null;
  }
}
