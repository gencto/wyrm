import 'package:equatable/equatable.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/services.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';

import '../buttons/problems_pill.dart';
import '../containers/fault_boundary.dart';
import '../containers/refresh_frame.dart';
import '../indicators/app_icon.dart';
import '../overlays/problems_drawer.dart';
import '../overlays/review_panel.dart';
import '../overlays/search_palette.dart';
import 'studio_shell.dart';
import 'top_bar.dart';
import 'window_bar.dart';
import 'window_controls.dart';
import 'workspace_rail.dart';

// What the Studio shell is drawn from (docs/studio.md §7.1), as typed
// values: the connector maps the domain into these; `StudioFrame` words
// them in the language on screen and draws them with [StudioShell],
// [TopBar], [ProblemsDrawer] and [ReviewPanel] (studio-rules §3, §5).

/// A workspace of the rail, in its order, with its icon and its name.
enum WorkspaceTab {
  explorer('ws_explorer'),
  links('ws_links'),
  flows('ws_flows'),
  history('ws_history'),
  access('ws_access'),
  sites('ws_sites'),
  assistant('ws_assistant'),
  system('ws_system');

  const WorkspaceTab(this.icon);

  final String icon;

  String get label => switch (this) {
    explorer => S.current.wsExplorer,
    links => S.current.wsLinks,
    flows => S.current.wsFlows,
    history => S.current.wsHistory,
    access => S.current.wsAccess,
    sites => S.current.wsSites,
    assistant => S.current.wsAssistant,
    system => S.current.wsSystem,
  };
}

/// How a site the session reaches is tied to the one it logged into, by
/// the word the search palette shows (the same in every language).
enum SiteTie {
  self('this'),
  downstream('downstream'),
  upstream('upstream');

  const SiteTie(this.word);

  final String word;
}

/// A site of the switcher.
final class SiteChoiceVm extends Equatable {
  const SiteChoiceVm({required this.site, required this.tie, this.via});

  final String site;
  final SiteTie tie;

  /// The site it is reached through, when not directly.
  final String? via;

  @override
  List<Object?> get props => [site, tie, via];
}

/// A staged change, with the level it needs and the user's on its key.
final class ReviewCardData extends Equatable {
  const ReviewCardData({
    required this.id,
    required this.op,
    required this.key,
    required this.field,
    required this.from,
    required this.to,
    required this.level,
    required this.have,
    required this.allowed,
  });

  final String id;
  final String op;
  final String key;
  final String field;
  final String from;
  final String to;
  final String level;
  final String have;
  final bool allowed;

  @override
  List<Object?> get props => [
    id,
    op,
    key,
    field,
    from,
    to,
    level,
    have,
    allowed,
  ];
}

/// A link of the site, for the search palette.
final class SearchLinkVm extends Equatable {
  const SearchLinkVm({required this.id, this.driver});

  final String id;
  final String? driver;

  @override
  List<Object?> get props => [id, driver];
}

/// A node of the tree, for the search palette.
final class SearchNodeVm extends Equatable {
  const SearchNodeVm({
    required this.key,
    required this.title,
    this.profile,
    this.value = false,
  });

  final String key;
  final String title;
  final String? profile;
  final bool value;

  @override
  List<Object?> get props => [key, title, profile, value];
}

/// What the search palette picked.
sealed class SearchPick extends Equatable {
  const SearchPick();
}

/// A workspace of the rail.
final class PickWorkspace extends SearchPick {
  const PickWorkspace(this.tab);

  final WorkspaceTab tab;

  @override
  List<Object?> get props => [tab];
}

/// A site to view.
final class PickSite extends SearchPick {
  const PickSite(this.site);

  final String site;

  @override
  List<Object?> get props => [site];
}

/// A node to show in Explorer, by its full key.
final class PickKey extends SearchPick {
  const PickKey(this.key);

  final String key;

  @override
  List<Object?> get props => [key];
}

/// What the shell draws.
final class StudioFrameVm extends Equatable {
  const StudioFrameVm({
    required this.site,
    required this.root,
    required this.user,
    required this.role,
    required this.locale,
    required this.theme,
    this.home = true,
    this.via = const [],
    this.sites = const [],
    this.connected = true,
    this.changes = 0,
    this.problemsCount,
    this.problemsBad = false,
    this.problemsOpen = false,
    this.problems = const [],
    this.quarantined = 0,
    this.reviewOpen = false,
    this.reviewError,
    this.applying = false,
    this.cards = const [],
    this.level = '',
    this.audit = 'sys/audit',
    this.links = const [],
    this.nodes = const [],
    this.refreshing = const ISetConst({}),
    this.window = const WindowBarVm(),
  });

  /// The site on screen and its root (`wy/<site>`).
  final String site;
  final String root;

  /// The site on screen is the one logged into.
  final bool home;

  /// The sites it is reached through.
  final List<String> via;
  final List<SiteChoiceVm> sites;
  final bool connected;
  final int changes;
  final String user;
  final String role;
  final String locale;
  final ThemeMode theme;

  /// What the problems pill counts; null hides it.
  final int? problemsCount;
  final bool problemsBad;
  final bool problemsOpen;

  /// Every failure of this session, newest first.
  final List<ProblemVm> problems;
  final int quarantined;
  final bool reviewOpen;
  final String? reviewError;
  final bool applying;
  final List<ReviewCardData> cards;

  /// The user's level under `downstream` of the site on screen.
  final String level;

  /// `sys/audit/<link>` the applied writes are recorded in.
  final String audit;
  final List<SearchLinkVm> links;
  final List<SearchNodeVm> nodes;

  /// The workspaces reading again what they show.
  final ISet<WorkspaceTab> refreshing;

  /// The frameless window's side of the top bar.
  final WindowBarVm window;

  @override
  List<Object?> get props => [
    site,
    root,
    home,
    via,
    sites,
    connected,
    changes,
    user,
    role,
    locale,
    theme,
    problemsCount,
    problemsBad,
    problemsOpen,
    problems,
    quarantined,
    reviewOpen,
    reviewError,
    applying,
    cards,
    level,
    audit,
    links,
    nodes,
    refreshing,
    window,
  ];
}

/// The Studio shell from typed values: the top bar, the rail and the
/// workspace [child], the Problems drawer and the review panel. It words
/// them in the language on screen; ⌘K (Ctrl-K) opens the search palette,
/// whose pick goes to [onSearch]. [lock] wraps the shell (the idle lock,
/// ADR 0050 §1.4).
class StudioFrame extends StatelessWidget {
  const StudioFrame({
    required this.vm,
    required this.active,
    required this.child,
    required this.onTab,
    required this.onSite,
    required this.onSearch,
    required this.onReview,
    required this.onCloseReview,
    required this.onApply,
    required this.onDiscard,
    required this.onRemoveChange,
    required this.onLogOut,
    required this.onSecurity,
    required this.onProblems,
    required this.onClearProblems,
    required this.onRetryProblem,
    required this.onProblemDetails,
    required this.onLanguage,
    required this.onTheme,
    this.lock,
    super.key,
  });

  final StudioFrameVm vm;
  final WorkspaceTab active;
  final Widget child;
  final TransitionBuilder? lock;
  final ValueChanged<WorkspaceTab> onTab;
  final ValueChanged<String> onSite;
  final ValueChanged<SearchPick> onSearch;
  final VoidCallback onReview;
  final VoidCallback onCloseReview;
  final VoidCallback onApply;
  final VoidCallback onDiscard;
  final ValueChanged<String> onRemoveChange;
  final VoidCallback onLogOut;
  final VoidCallback onSecurity;
  final VoidCallback onProblems;
  final VoidCallback onClearProblems;
  final ValueChanged<int> onRetryProblem;
  final ValueChanged<int> onProblemDetails;
  final ValueChanged<String> onLanguage;
  final ValueChanged<ThemeMode> onTheme;

  /// `…/plc1/t2`: the last two segments of a key.
  static String _short(String key) {
    final parts = key.split('/');
    return parts.length <= 3
        ? key
        : '…/${parts.sublist(parts.length - 2).join('/')}';
  }

  /// A key below the site (`downstream/plc1/t1`).
  static String _relative(String key) => key.split('/').skip(2).join('/');

  TopBarVm get _topBar {
    final s = S.current;
    return TopBarVm(
      site: vm.site,
      siteDetail: vm.via.isEmpty
          ? (vm.home ? s.thisBroker : null)
          : s.viaSite(vm.via.join(' · ')),
      sites: [
        for (final c in vm.sites)
          SiteItemVm(
            site: c.site,
            current: c.site == vm.site,
            detail: switch (c.tie) {
              SiteTie.self => s.thisBroker,
              SiteTie.upstream => s.upstream,
              SiteTie.downstream => c.via == null ? null : s.viaSite(c.via!),
            },
          ),
      ],
      connected: vm.connected,
      changes: vm.changes,
      reviewReason: s.nothingStaged,
      user: vm.user,
      role: vm.role,
      locale: vm.locale,
      theme: vm.theme,
      problems: switch (vm.problemsCount) {
        null => null,
        final n => ProblemsPillVm(
          label: s.problemsCount(n),
          bad: vm.problemsBad,
          open: vm.problemsOpen,
        ),
      },
    );
  }

  List<SearchEntryVm<SearchPick>> get _entries => [
    for (final t in WorkspaceTab.values)
      SearchEntryVm(id: PickWorkspace(t), title: t.label, icon: t.icon),
    for (final c in vm.sites)
      SearchEntryVm(
        id: PickSite(c.site),
        title: c.site,
        icon: 'node_site',
        detail: c.tie.word,
      ),
    for (final l in vm.links)
      SearchEntryVm(
        id: PickKey('${vm.root}/downstream/${l.id}'),
        title: l.id,
        icon: 'node_link',
        detail: l.driver,
      ),
    for (final n in vm.nodes)
      SearchEntryVm(
        id: PickKey(n.key),
        title: n.title,
        icon: AppIcon.nodeName(
          key: n.key,
          root: vm.root,
          profile: n.profile,
          value: n.value,
        ),
        detail: _relative(n.key),
      ),
  ];

  /// The "Go to" entry for a typed key (with a `/`), full or below the site.
  SearchEntryVm<SearchPick>? _goTo(String text) {
    if (text.isEmpty || !text.contains('/')) {
      return null;
    }
    final key = text.startsWith('wy/') ? text : '${vm.root}/$text';
    return SearchEntryVm(
      id: PickKey(key),
      title: S.current.goTo(_relative(key)),
      icon: 'ui_chevron_right',
    );
  }

  Future<void> _search(BuildContext context) async {
    final picked = await SearchPalette.show(
      context,
      hint: S.current.searchHint,
      entries: _entries,
      goTo: _goTo,
    );
    if (picked != null) {
      onSearch(picked);
    }
  }

  List<ChangeCardVm> get _cards => [
    for (final c in vm.cards)
      ChangeCardVm(
        id: c.id,
        op: c.op,
        // a link's params: the whole key, so the site is never hidden
        key_: c.key.contains('/sys/links/') ? c.key : _short(c.key),
        field: c.field,
        from: c.from,
        to: c.to,
        allowed: c.allowed,
        levelText: c.allowed
            ? S.current.needsLevelYouHaveIt(c.level)
            : S.current.needsLevelYouHave(c.level, c.have),
      ),
  ];

  @override
  Widget build(BuildContext context) {
    final s = S.current;
    final blocked = vm.cards.where((c) => !c.allowed).length;
    void search() => _search(context).ignore();
    final shell = StudioShell(
      selected: active.index,
      onSelect: (i) => onTab(WorkspaceTab.values[i]),
      more: s.more,
      offline: vm.connected ? null : s.offline,
      rail: [
        for (final t in WorkspaceTab.values)
          RailItemVm(
            icon: t.icon,
            label: t.label,
            badge: t == WorkspaceTab.links && vm.quarantined > 0
                ? '${vm.quarantined}'
                : null,
          ),
      ],
      topBar: (context, compact, _) => TopBar(
        vm: _topBar,
        window: vm.window,
        compact: compact,
        labels: TopBarLabels(
          search: s.searchHint,
          review: s.reviewAndApply,
          reviewShort: s.review,
        ),
        onSite: onSite,
        onSearch: search,
        onReview: onReview,
        onLogOut: onLogOut,
        onSecurity: onSecurity,
        onProblems: onProblems,
        onLanguage: onLanguage,
        onTheme: onTheme,
      ),
      side: !vm.problemsOpen
          ? null
          : FaultBoundary(
              panel: .drawer,
              child: ProblemsDrawer(
                problems: vm.problems,
                labels: ProblemsLabels(
                  title: s.problemsTitle,
                  clear: s.problemsClear,
                  close: s.problemsClose,
                  note: s.problemsNote,
                  empty: s.problemsEmpty,
                  details: s.errDetails,
                  retry: s.errTryAgain,
                  shown: s.problemsShown,
                ),
                onClose: onProblems,
                onClear: onClearProblems,
                onRetry: onRetryProblem,
                onDetails: onProblemDetails,
              ),
            ),
      onScrim: onCloseReview,
      drawerTop: vm.window.trailing > 0 ? WindowControls.height : 0,
      drawer: !vm.reviewOpen
          ? null
          : ReviewPanel(
              cards: _cards,
              error: vm.reviewError,
              applying: vm.applying,
              labels: ReviewLabels(
                title: s.stagedChanges(vm.cards.length),
                rights: s.rightsLine(vm.site, vm.user, vm.role, vm.level),
                apply: s.applyChanges(vm.cards.length - blocked),
                ask: blocked == 0 ? null : s.askAdminFor(blocked),
                askReason: s.askAdminReason,
                discard: s.discardAll,
                empty: s.nothingStaged,
                note: s.reviewNote(vm.audit),
                audit: vm.audit,
                refused: s.brokerRefused,
                close: s.closeLabel,
              ),
              onApply: onApply,
              onDiscard: onDiscard,
              onClose: onCloseReview,
              onRemove: onRemoveChange,
            ),
      // Stale while revalidate (docs/studio.md §6.7): the workspace keeps
      // its content while it reads again.
      child: RefreshFrame(
        refreshing: vm.refreshing.contains(active),
        label: s.updating,
        // A workspace that throws while it builds is replaced by a card;
        // the shell and the other tabs keep working
        // (docs/design/specs/errors.md §5).
        child: FaultBoundary(panel: .workspace, child: child),
      ),
    );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): search,
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): search,
      },
      child: Focus(
        autofocus: true,
        child: lock?.call(context, shell) ?? shell,
      ),
    );
  }
}
