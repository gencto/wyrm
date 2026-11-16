import 'dart:async';

import 'package:async_redux/async_redux.dart';
import 'package:auto_route/auto_route.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/changes/actions/apply_changes_action.dart';
import 'package:business/redux/changes/actions/discard_changes_action.dart';
import 'package:business/redux/changes/actions/remove_change_action.dart';
import 'package:business/redux/changes/actions/set_open_action.dart';
import 'package:business/redux/language/actions/set_language_action.dart';
import 'package:business/redux/problems/actions/clear_problems_action.dart';
import 'package:business/redux/problems/actions/open_problems_action.dart';
import 'package:business/redux/problems/actions/retry_problem_action.dart';
import 'package:business/redux/session/actions/log_out_action.dart';
import 'package:business/redux/site/actions/retrieve_sites_action.dart';
import 'package:business/redux/site/actions/switch_site_action.dart';
import 'package:business/redux/theme/actions/set_theme_mode_action.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:material_ui/material_ui.dart';
import 'package:models/workspace.dart';
import 'package:ui/shell/studio_frame.dart';

import '../common/window.dart';
import '../dialogs/error_dialogs.dart';
import '../dialogs/security_dialogs.dart';
import '../errors.dart';
import '../mappers/rights_mappers.dart';
import '../mappers/shell_mappers.dart';
import '../navigation/go_action.dart';
import '../navigation/leave_on_log_out_action.dart';
import '../navigation/search_go_action.dart';
import '../navigation/workspace_routes.dart';
import 'lock_overlay_connector.dart';

/// The Studio shell: top bar, rail and the workspace tabs, with the review
/// panel of staged changes on the right when it is open. The connector
/// reads selectors (`business/lib/wyrm/shell.dart`), maps them through
/// `app/lib/mappers/shell_mappers.dart`, and `StudioFrame` words them; one
/// action per intent.
@RoutePage()
class StudioPageConnector extends StatelessWidget {
  const StudioPageConnector({super.key});

  @override
  Widget build(BuildContext context) => AutoTabsRouter(
    routes: workspaceRoutes,
    builder: (context, child) => StoreConnector<AppState, _Vm>(
      debug: this,
      vm: () => _Factory(this),
      onInit: (store) => store.dispatch(RetrieveSitesAction()),
      builder: (context, vm) => StudioFrame(
        vm: vm.frame,
        active: Workspace.values[AutoTabsRouter.of(context).activeIndex].tab,
        // The idle lock covers the whole shell (ADR 0050 §1.4).
        lock: (context, shell) =>
            LockOverlayConnector(onLogOut: vm.onLogOut, child: shell!),
        onTab: vm.onTab,
        onSite: vm.onSite,
        onSearch: vm.onSearch,
        onReview: vm.onReview,
        onCloseReview: vm.onCloseReview,
        onApply: vm.onApply,
        onDiscard: vm.onDiscard,
        onRemoveChange: vm.onRemoveChange,
        onLogOut: vm.onLogOut,
        onSecurity: () => unawaited(showSecurityDialog(context)),
        onProblems: vm.onProblems,
        onClearProblems: vm.onClearProblems,
        onRetryProblem: vm.onRetryProblem,
        onProblemDetails: (id) => unawaited(showProblemDetails(context, id)),
        onLanguage: vm.onLanguage,
        onTheme: vm.onTheme,
        child: child,
      ),
    ),
  );
}

/// Factory that creates a view-model for the StoreConnector.
class _Factory extends VmFactory<AppState, StudioPageConnector, _Vm>
    with Selectors {
  _Factory(super._connector);

  @override
  _Vm fromStore() {
    final pill = problems.pill;
    return _Vm(
      frame: StudioFrameVm(
        site: site.viewed ?? '',
        root: site.root ?? '',
        home: site.viewsHome,
        via: site.viewedVia,
        sites: [for (final c in site.choices) c.vm],
        connected: site.connected,
        changes: changes.view.length,
        user: site.user ?? '',
        role: site.role ?? '',
        locale: language.locale,
        theme: theme.mode,
        problemsCount: pill?.count,
        problemsBad: pill?.bad ?? false,
        problemsOpen: problems.open,
        problems: [for (final e in problems.items) problemVm(e)],
        quarantined: quarantine.view.length,
        reviewOpen: changes.open,
        reviewError: changes.message,
        applying: changes.isWaiting,
        cards: [for (final c in changes.reviewCards) c.data],
        level: site.downstreamLevel.access,
        audit: changes.reviewAudit,
        links: [
          for (final id in links.view)
            SearchLinkVm(id: id, driver: links.table[id]?.driver),
        ],
        nodes: [for (final n in nodes.searchNodes) n.vm],
        refreshing: {for (final w in refreshingWorkspaces) w.tab}.lock,
        window: windowBar(fullScreen: window.fullScreen),
      ),
      onTab: (t) => dispatch(GoAction.workspace(t.workspace)),
      onSite: (s) => dispatch(SwitchSiteAction(s)),
      onSearch: (pick) => dispatch(SearchGoAction(pick)),
      onReview: () => dispatch(SetOpenAction(true)),
      onCloseReview: () => dispatch(SetOpenAction(false)),
      onApply: () => dispatch(ApplyChangesAction()),
      onDiscard: () => dispatch(DiscardChangesAction()),
      onRemoveChange: (id) => dispatch(RemoveChangeAction(id)),
      onLogOut: () => dispatch(LeaveOnLogOutAction(LogOutAction())),
      onProblems: () => dispatchSync(OpenProblemsAction(open: !problems.open)),
      onClearProblems: () => dispatchSync(ClearProblemsAction()),
      onRetryProblem: (id) => dispatch(RetryProblemAction(id)),
      onLanguage: (code) => dispatchSync(SetLanguageAction(code)),
      onTheme: (mode) => dispatchSync(SetThemeModeAction(mode)),
    );
  }
}

/// What the shell draws ([frame], compared) and what it starts (not).
class _Vm extends Vm {
  _Vm({
    required this.frame,
    required this.onTab,
    required this.onSite,
    required this.onSearch,
    required this.onReview,
    required this.onCloseReview,
    required this.onApply,
    required this.onDiscard,
    required this.onRemoveChange,
    required this.onLogOut,
    required this.onProblems,
    required this.onClearProblems,
    required this.onRetryProblem,
    required this.onLanguage,
    required this.onTheme,
  }) : super(equals: [frame]);

  final StudioFrameVm frame;
  final ValueChanged<WorkspaceTab> onTab;
  final ValueChanged<String> onSite;
  final ValueChanged<SearchPick> onSearch;
  final VoidCallback onReview;
  final VoidCallback onCloseReview;
  final VoidCallback onApply;
  final VoidCallback onDiscard;
  final ValueChanged<String> onRemoveChange;
  final VoidCallback onLogOut;
  final VoidCallback onProblems;
  final VoidCallback onClearProblems;
  final ValueChanged<int> onRetryProblem;

  /// The account menu's Language (a locale code of the ARB files) and
  /// Theme (owner decision 2026-11-09).
  final ValueChanged<String> onLanguage;
  final ValueChanged<ThemeMode> onTheme;
}
