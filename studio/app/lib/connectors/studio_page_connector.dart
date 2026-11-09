import 'dart:async';

import 'package:async_redux/async_redux.dart';
import 'package:auto_route/auto_route.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/changes/actions/apply_changes_action.dart';
import 'package:business/redux/changes/actions/discard_changes_action.dart';
import 'package:business/redux/changes/actions/remove_change_action.dart';
import 'package:business/redux/changes/actions/set_open_action.dart';
import 'package:business/redux/nodes/actions/set_selected_node_action.dart';
import 'package:business/redux/session/actions/log_out_action.dart';
import 'package:business/redux/site/actions/retrieve_sites_action.dart';
import 'package:business/redux/site/actions/view_site_action.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:localization/localization.dart';
import 'package:ui/indicators/app_icon.dart';
import 'package:ui/overlays/review_panel.dart';
import 'package:ui/overlays/search_palette.dart';
import 'package:ui/shell/studio_shell.dart';
import 'package:ui/shell/top_bar.dart';
import 'package:ui/shell/workspace_rail.dart';

import '../common/changes.dart';
import '../navigation/app_router.dart';
import '../navigation/go_action.dart';

/// The eight workspaces, in rail order (docs/studio.md §7.1).
const List<PageRouteInfo> _tabs = [
  ExplorerRoute(),
  LinksRoute(),
  FlowsRoute(),
  HistoryRoute(),
  AccessRoute(),
  SitesRoute(),
  AssistantRoute(),
  SystemRoute(),
];

const _tabIds = [
  'explorer',
  'links',
  'flows',
  'history',
  'access',
  'sites',
  'assistant',
  'system',
];

const _icons = [
  'ws_explorer',
  'ws_links',
  'ws_flows',
  'ws_history',
  'ws_access',
  'ws_sites',
  'ws_assistant',
  'ws_system',
];

List<String> get _labels => [
  S.current.wsExplorer,
  S.current.wsLinks,
  S.current.wsFlows,
  S.current.wsHistory,
  S.current.wsAccess,
  S.current.wsSites,
  S.current.wsAssistant,
  S.current.wsSystem,
];

/// The Studio shell: top bar, rail and the workspace tabs, with the review
/// panel of staged changes on the right when it is open.
@RoutePage()
class StudioPageConnector extends StatelessWidget {
  const StudioPageConnector({super.key});

  @override
  Widget build(BuildContext context) => AutoTabsRouter(
    routes: _tabs,
    builder: (context, child) {
      final tabs = AutoTabsRouter.of(context);
      return StoreConnector<AppState, _Vm>(
        debug: this,
        vm: () => _Factory(this),
        onInit: (store) =>
            unawaited(store.dispatchAndWait(RetrieveSitesAction())),
        builder: (context, vm) => CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () =>
                _search(context, vm, tabs),
            const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
                _search(context, vm, tabs),
          },
          child: Focus(
            autofocus: true,
            child: StudioShell(
              selected: tabs.activeIndex,
              onSelect: tabs.setActiveIndex,
              more: S.current.more,
              offline: vm.connected ? null : S.current.offline,
              rail: [
                for (var i = 0; i < _tabs.length; i++)
                  RailItemVm(
                    icon: _icons[i],
                    label: _labels[i],
                    badge: i == 1 ? vm.quarantineBadge : null,
                  ),
              ],
              topBar: (compact) => TopBar(
                vm: vm.topBar,
                compact: compact,
                labels: TopBarLabels(
                  search: S.current.searchHint,
                  review: S.current.reviewAndApply,
                  reviewShort: S.current.review,
                  logOut: S.current.logOut,
                ),
                onSite: vm.onSite,
                onSearch: () => _search(context, vm, tabs),
                onReview: vm.onReview,
                onLogOut: vm.onLogOut,
              ),
              child: Row(
                crossAxisAlignment: .stretch,
                children: [
                  Expanded(child: child),
                  if (vm.reviewOpen)
                    ReviewPanel(
                      cards: vm.cards,
                      error: vm.reviewError,
                      applying: vm.applying,
                      labels: ReviewLabels(
                        title: S.current.stagedChanges(vm.cards.length),
                        apply: S.current.apply,
                        discard: S.current.discard,
                        empty: S.current.nothingStaged,
                        note: S.current.stagedNote,
                        refused: S.current.brokerRefused,
                      ),
                      onApply: vm.onApply,
                      onDiscard: vm.onDiscard,
                      onClose: vm.onCloseReview,
                      onRemove: vm.onRemoveChange,
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );

  Future<void> _search(
    BuildContext context,
    _Vm vm,
    TabsRouter tabs,
  ) async {
    final picked = await SearchPalette.show(
      context,
      hint: S.current.searchHint,
      entries: vm.searchEntries,
      goTo: vm.goTo,
    );
    if (picked == null) {
      return;
    }
    final (kind, value) = (
      picked.substring(0, picked.indexOf(':')),
      picked.substring(picked.indexOf(':') + 1),
    );
    switch (kind) {
      case 'tab':
        tabs.setActiveIndex(_tabIds.indexOf(value));
      case 'site':
        vm.onSite(value);
      case 'key':
        vm.onGoToKey(value);
        tabs.setActiveIndex(0);
    }
  }
}

/// Factory that creates a view-model for the StoreConnector.
class _Factory extends VmFactory<AppState, StudioPageConnector, _Vm>
    with Selectors {
  _Factory(super._connector);

  @override
  _Vm fromStore() {
    final home = site.name ?? '';
    final viewed = site.viewed ?? home;
    final here = site.choices.where((c) => c.site == viewed).firstOrNull;
    final route = [
      ?here?.via,
      if (viewed != home) home,
    ];
    final quarantined = quarantine.view.length;
    return _Vm(
      connected: site.connected,
      topBar: TopBarVm(
        site: viewed,
        siteDetail: route.isEmpty ? null : S.current.viaSite(route.join(' · ')),
        sites: [
          for (final c in site.choices)
            SiteItemVm(
              site: c.site,
              current: c.site == viewed,
              detail: switch (c.relation) {
                'this' => S.current.thisBroker,
                'upstream' => S.current.upstream,
                _ => c.via == null ? null : S.current.viaSite(c.via!),
              },
            ),
        ],
        connected: site.connected,
        changes: changes.view.length,
        reviewReason: S.current.nothingStaged,
        user: site.user ?? '',
        role: site.role ?? '',
      ),
      quarantineBadge: quarantined == 0 ? null : '$quarantined',
      reviewOpen: changes.open,
      reviewError: changes.message,
      applying: changes.isWaiting,
      cards: changeCards(this),
      searchEntries: [
        for (var i = 0; i < _tabIds.length; i++)
          SearchEntryVm(
            id: 'tab:${_tabIds[i]}',
            title: _labels[i],
            icon: _icons[i],
          ),
        for (final c in site.choices)
          SearchEntryVm(
            id: 'site:${c.site}',
            title: c.site,
            icon: 'node_site',
            detail: c.relation,
          ),
        for (final id in links.view)
          SearchEntryVm(
            id: 'key:${site.root}/downstream/$id',
            title: id,
            icon: 'node_link',
            detail: links.table[id]?.driver,
          ),
        for (final k in nodes.view.take(400))
          SearchEntryVm(
            id: 'key:$k',
            title: nodes.table[k]?.name ?? k,
            icon: AppIcon.nodeName(
              key: k,
              root: site.root ?? '',
              profile: nodes.table[k]?.profile,
              type: nodes.table[k]?.type,
            ),
            detail: _relative(k),
          ),
      ],
      goTo: (text) {
        if (text.isEmpty || !text.contains('/')) {
          return null;
        }
        final key = text.startsWith('wy/') ? text : '${site.root}/$text';
        return SearchEntryVm(
          id: 'key:$key',
          title: S.current.goTo(_relative(key)),
          icon: 'ui_chevron_right',
        );
      },
      onSite: (s) => dispatch(ViewSiteAction(s)),
      onGoToKey: (k) => dispatch(SetSelectedNodeAction(k)),
      onReview: () => dispatch(SetOpenAction(true)),
      onCloseReview: () => dispatch(SetOpenAction(false)),
      onApply: () => unawaited(dispatchAndWait(ApplyChangesAction())),
      onDiscard: () => dispatch(DiscardChangesAction()),
      onRemoveChange: (id) => dispatch(RemoveChangeAction(id)),
      onLogOut: () async {
        await dispatchAndWait(LogOutAction());
        dispatch(GoAction.replace(const LogInRoute()));
      },
    );
  }

  String _relative(String key) => key.split('/').skip(2).join('/');
}

/// The view-model holds the part of the Store state the dumb-widget needs.
class _Vm extends Vm {
  _Vm({
    required this.connected,
    required this.topBar,
    required this.quarantineBadge,
    required this.reviewOpen,
    required this.reviewError,
    required this.applying,
    required this.cards,
    required this.searchEntries,
    required this.goTo,
    required this.onSite,
    required this.onGoToKey,
    required this.onReview,
    required this.onCloseReview,
    required this.onApply,
    required this.onDiscard,
    required this.onRemoveChange,
    required this.onLogOut,
  }) : super(
         equals: [
           connected,
           topBar,
           quarantineBadge,
           reviewOpen,
           reviewError,
           applying,
           cards,
           searchEntries,
         ],
       );

  final bool connected;
  final TopBarVm topBar;
  final String? quarantineBadge;
  final bool reviewOpen;
  final String? reviewError;
  final bool applying;
  final List<ChangeCardVm> cards;
  final List<SearchEntryVm> searchEntries;
  final SearchEntryVm? Function(String text) goTo;
  final ValueChanged<String> onSite;
  final ValueChanged<String> onGoToKey;
  final VoidCallback onReview;
  final VoidCallback onCloseReview;
  final VoidCallback onApply;
  final VoidCallback onDiscard;
  final ValueChanged<String> onRemoveChange;
  final VoidCallback onLogOut;
}
