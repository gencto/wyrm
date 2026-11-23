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
/// would on its own. This action changes no state (`null`) and is not a
/// `WaitingAction`: no screen draws "reloading", so nothing asks the store
/// about it and the store tells no widget when it starts or ends. A screen
/// that one day shows it mixes `WaitingAction` in and reads
/// `waiting.on<ReloadShownAction>()`.
class ReloadShownAction extends Action {
  @override
  Future<AppState?> reduce() async {
    await dispatchAndWaitAll([
      if (links.view.isNotEmpty) RetrieveLinksAction(),
      if (quarantine.view.isNotEmpty) RetrieveQuarantineAction(),
      if (packages.view.isNotEmpty) RetrievePackagesAction(),
      // a shown screen that offers backups (System's card, Links'
      // buttons) reads them again, whatever the last read gave: after a
      // site switch they are the new site's, not read yet
      if (system.shown || links.shown) RetrieveBackupsAction(quiet: true),
      // the Assistant reads its agent again: after a site switch it is the
      // new site's agent, with its own tasks
      if (assistant.shown) LoadAssistantAction(),
    ]);
    return null;
  }
}
