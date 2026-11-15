import 'dart:async';

import 'package:async_redux/async_redux.dart';
import 'package:auto_route/auto_route.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/assistant/actions/set_drawer_action.dart';
import 'package:business/redux/nodes/actions/check_points_action.dart';
import 'package:business/redux/nodes/actions/clear_selection_action.dart';
import 'package:business/redux/nodes/actions/close_node_menu_action.dart';
import 'package:business/redux/nodes/actions/copy_keys_action.dart';
import 'package:business/redux/nodes/actions/copy_value_action.dart';
import 'package:business/redux/nodes/actions/hide_explorer_action.dart';
import 'package:business/redux/nodes/actions/invoke_node_action.dart';
import 'package:business/redux/nodes/actions/mark_nodes_action.dart';
import 'package:business/redux/nodes/actions/open_explorer_tab_action.dart';
import 'package:business/redux/nodes/actions/open_node_menu_action.dart';
import 'package:business/redux/nodes/actions/pick_history_range_action.dart';
import 'package:business/redux/nodes/actions/pick_node_action_action.dart';
import 'package:business/redux/nodes/actions/remove_checked_action.dart';
import 'package:business/redux/nodes/actions/retry_read_action.dart';
import 'package:business/redux/nodes/actions/rewatch_explorer_action.dart';
import 'package:business/redux/nodes/actions/select_node_action.dart';
import 'package:business/redux/nodes/actions/select_point_action.dart';
import 'package:business/redux/nodes/actions/set_action_action.dart';
import 'package:business/redux/nodes/actions/set_history_window_action.dart';
import 'package:business/redux/nodes/actions/set_point_filter_action.dart';
import 'package:business/redux/nodes/actions/set_tree_filter_action.dart';
import 'package:business/redux/nodes/actions/set_viewed_point_action.dart';
import 'package:business/redux/nodes/actions/show_explorer_action.dart';
import 'package:business/redux/nodes/actions/stage_invoke_action.dart';
import 'package:business/redux/nodes/actions/stage_point_edit_action.dart';
import 'package:business/redux/nodes/actions/stage_poll_action.dart';
import 'package:business/redux/nodes/actions/stage_value_action.dart';
import 'package:business/redux/nodes/actions/toggle_node_action.dart';
import 'package:business/redux/nodes/actions/zoom_history_action.dart';
import 'package:business/redux/panels/actions/set_panel_width_action.dart';
import 'package:business/wyrm/calls.dart' show clearedNames;
import 'package:business/wyrm/explorer.dart';
import 'package:business/wyrm/keys.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/charts/trend.dart';
import 'package:ui/containers/action_card.dart';
import 'package:ui/containers/side_panels.dart';
import 'package:ui/forms/action_form.dart';
import 'package:ui/indicators/app_icon.dart';
import 'package:ui/indicators/fail_chip.dart';
import 'package:ui/indicators/node_state.dart';
import 'package:ui/indicators/status_pill.dart';
import 'package:ui/models/disabled.dart';
import 'package:ui/models/submit.dart';
import 'package:ui/overlays/value_viewer.dart';
import 'package:ui/pages/explorer_page.dart';
import 'package:ui/tables/points_table.dart';
import 'package:ui/trees/tree_row.dart';

import '../common/forms.dart';
import '../common/side_panels.dart';
import '../common/tab_visibility.dart';
import '../common/value_viewer.dart';
import '../mappers/explorer_mappers.dart';
import '../navigation/app_router.dart';
import '../navigation/go_action.dart';
import 'assistant_page_connector.dart';

/// Explorer (docs/design/specs/explorer.md): the tree of the site on screen,
/// the node on screen and the inspector. It reads `explorer` (what is shown,
/// computed in `business/lib/wyrm/explorer.dart`), maps it through
/// `app/lib/mappers/explorer_mappers.dart` and starts one action per intent;
/// the page says the words (studio-rules §3, §5, §9).
@RoutePage()
class ExplorerPageConnector extends StatelessWidget {
  const ExplorerPageConnector({super.key});

  @override
  Widget build(BuildContext context) => StoreConnector<AppState, _Vm>(
    debug: this,
    vm: () => _Factory(this),
    // The keys on screen changed (another node, a viewer): watched again,
    // in one action that does nothing while the tab is hidden.
    onWillChange: (_, store, before, now) {
      if (!_sameKeys(before.watch, now.watch)) {
        store.dispatchSync(RewatchExplorerAction());
      }
    },
    builder: (_, vm) => TabVisibility(
      onShow: vm.onShow,
      onHide: vm.onHide,
      child: ExplorerPage(
        site: vm.site,
        tree: vm.tree,
        treeLoading: vm.treeLoading,
        treeFilter: vm.treeFilter,
        onTreeFilter: vm.onTreeFilter,
        onNoteLink: vm.onNoteLink,
        onTap: vm.onSelect,
        onToggle: vm.onToggle,
        onMark: vm.onMark,
        onMarkRange: vm.onMarkRange,
        onOpenMenu: vm.onOpenMenu,
        menu: vm.menu,
        menuOpening: vm.menuOpening,
        onMenuShown: vm.onMenuShown,
        onMenuPick: vm.onMenuPick,
        keyName: vm.keyName,
        keyLinks: vm.keyLinks,
        copyKeys: vm.copyKeys,
        onCopy: vm.onCopy,
        onCopyValue: vm.onCopyValue,
        onClear: vm.onClear,
        onToggleAssistant: vm.onToggleAssistant,
        title: vm.title,
        titleName: vm.titleName,
        pill: vm.pill,
        subtitle: vm.subtitle,
        headerButtons: vm.headerButtons,
        flowId: vm.flowId,
        flowDisabled: vm.flowDisabled,
        onTapFlowEditor: vm.onTapFlowEditor,
        onTool: vm.onTool,
        tabs: vm.tabs,
        tab: vm.tab,
        onTab: vm.onTab,
        toolbar: vm.toolbar,
        selectionBar: vm.selectionBar,
        polls: explorerPolls,
        onSetPoll: vm.onSetPoll,
        pointFilter: vm.pointFilter,
        onPointFilter: vm.onPointFilter,
        points: vm.points,
        pointsLoading: vm.pointsLoading,
        pointsEmpty: vm.pointsEmpty,
        emptyButtons: vm.emptyButtons,
        children: vm.children,
        onChild: vm.onSelect,
        onPoint: vm.onPoint,
        onCheck: vm.onCheck,
        onRange: vm.onRange,
        onCheckAll: vm.onCheckAll,
        params: vm.params,
        onParam: vm.onParam,
        actionGroups: vm.actionGroups,
        onAction: vm.onAction,
        result: vm.result,
        range: vm.range,
        onHistoryRange: vm.onHistoryRange,
        trend: vm.trend,
        onTrendWindow: (a, b) => vm.onTrendWindow((start: a, end: b)),
        onTrendReset: vm.onTrendReset,
        historyRows: vm.historyRows,
        historyNoPoint: vm.historyNoPoint,
        historyFailed: vm.historyFailed,
        auditRows: vm.auditRows,
        auditNote: vm.auditNote,
        inspector: vm.inspector,
        submit: vm.submit,
        onReadAgain: vm.onReadAgain,
        onCloseInspector: vm.onCloseInspector,
        panels: vm.panelWidths,
        onPanelWidth: (side, w) => vm.onPanelWidth((side: side, width: w)),
        viewer: vm.viewer,
        viewerTables: viewerTables,
        onViewPoint: vm.onViewPoint,
        onCloseViewer: vm.onCloseViewer,
        drawer: vm.assistantOpen ? const AssistantDrawerConnector() : null,
      ),
    ),
  );

  static bool _sameKeys(List<String> a, List<String> b) =>
      a.length == b.length && a.every(b.contains);
}

/// Factory that creates a view-model for the StoreConnector.
class _Factory extends VmFactory<AppState, ExplorerPageConnector, _Vm>
    with Selectors {
  _Factory(super._connector);

  @override
  _Vm fromStore() {
    final x = explorer;
    final sel = x.selected;
    final selection = x.selection;
    final answer = x.answer;
    final cards = x.actionCards;
    final history = x.history;
    final point = nodes.point;
    final canAudit = x.canAudit;
    final toolbar = sel == null ? const <ToolButtonVm>[] : _toolbar(x);
    final name = sel?.split('/').last;
    return _Vm(
      site: site.viewed ?? '',
      tree: [for (final r in x.treeRows) _treeRow(r)],
      treeLoading: nodes.view.isEmpty && nodes.isWaiting,
      treeFilter: nodes.treeFilter,
      watch: x.watchKeys,
      keyName: sel,
      keyLinks: parentLinksOf(sel, sections: explorerSections),
      title: x.shownDisplay ?? name,
      titleName: x.shownDisplay == null ? null : name,
      pill: switch (x.pill) {
        FlowPill(:final flow) => flow.tag.pill(flow.version),
        LinkPill(:final state) => state.node.pill(),
        BrokerPill(:final connected) =>
          (connected ? NodeState.connected : NodeState.offline).pill(
            ring: false,
          ),
        DriverPill(:final name, :final status) => StatusPillVm(
          label: name,
          tone: status.tone,
          mark: status.tone == .warn ? .ring : .dot,
        ),
        null => null,
      },
      subtitle: switch (x.subtitle) {
        final s? => ExplorerSubtitleVm(
          kind: s.kind.tag,
          driver: s.driver,
          deployedBy: s.deployedBy,
          problem: s.problem,
          unit: s.unit,
          host: s.host,
          port: s.port,
          serialPort: s.serialPort,
          root: s.root,
          children: s.children,
          lastRead: s.lastRead,
          description: s.description,
        ),
        null => null,
      },
      headerButtons: [
        if (x.ping case final r?)
          ToolButtonVm(.ping, disabled: r.disabled(missing: .ping)),
      ],
      flowId: x.flowId,
      flowDisabled: switch (x.flowEditor) {
        LacksLevel() => const NotThere(.readFlow),
        _ => null,
      },
      tabs: [
        for (final (t, n) in x.tabs) ExplorerTabVm(t.tag, count: n),
      ],
      tab: x.tab.tag,
      toolbar: toolbar,
      selectionBar: switch (selection) {
        final s? => SelectionBarVm(
          count: s.count,
          buttons: [
            const ToolButtonVm(.copyKeys),
            ToolButtonVm(
              .setPoll,
              disabled: s.canSetPoll ? null : const NotThere(.edit),
            ),
            const ToolButtonVm(.record, disabled: NotThere(.historyAction)),
            ToolButtonVm(.removeChecked, disabled: s.remove.disabled()),
          ],
        ),
        null => null,
      },
      pointFilter: nodes.pointFilter,
      points: [for (final p in x.pointRows) p.vm],
      pointsLoading: x.pointsLoading,
      pointsEmpty: x.points.isNotEmpty
          ? null
          : (x.addsPoints ? PointsEmpty.noPointsYet : PointsEmpty.noPoints),
      emptyButtons: x.addsPoints
          ? [
              for (final b in toolbar)
                if (b.tool != .applyProfile) b,
            ]
          : const [],
      children: [for (final c in x.childRows) c.vm],
      params: [for (final s in x.params) s.vm],
      actionGroups: [
        for (final (staged, cards) in [
          (true, cards.staged),
          (false, cards.now),
        ])
          if (cards.isNotEmpty)
            ActionCardGroupVm(
              staged: staged,
              cards: [
                for (final c in cards)
                  ActionCardVm(
                    id: c.action.name,
                    title: c.title,
                    level: c.action.level.access,
                    params: c.action.params.length,
                    result: c.action.result,
                    selected: c.selected,
                    disabled: c.reach.disabled(),
                  ),
              ],
            ),
      ],
      result: switch (answer) {
        final a? => ResultVm(
          action: a.title,
          count: a.answer.count,
          columns: a.columns,
          rows: [for (final r in a.answer.rows) r.unlock],
          lines: a.answer.lines.unlock,
        ),
        null => null,
      },
      range: nodes.historyRange.tag,
      trend: x.trend?.vm,
      historyRows: [
        for (final h in history?.rows ?? const <ExplorerHistoryRow>[])
          HistoryRowVm(time: h.time, value: h.value, mark: h.quality?.sample),
      ],
      historyNoPoint: point == null,
      historyFailed: history?.failed,
      auditRows: [
        for (final e in x.auditRows)
          AuditRowVm(
            time: e.time,
            op: e.op,
            key: e.key,
            who: e.who,
            status: e.status,
          ),
      ],
      auditNote: !canAudit
          ? AuditNote.needsRights
          : (nodes.audit.isEmpty ? AuditNote.none : null),
      inspector: x.inspector?.vm,
      copyKeys: x.copyKeys,
      pointValue: x.pointValue,
      menu: x.menu?.vm,
      menuOpening: nodes.menuOpening,
      submit: SubmitVm(
        busy: nodes.isWaiting || changes.isWaiting,
        onSubmit: (values) => _submit(x.submit, values),
      ),
      assistantOpen: assistant.drawer,
      panelWidths: WorkspacePanels.explorer.widths(panels.widths),
      viewer: x.viewer?.vm,
      onShow: () => dispatch(ShowExplorerAction()),
      onHide: () => dispatchSync(HideExplorerAction()),
      onSelect: (k) => dispatch(SelectNodeAction(k)),
      onToggle: (k) => dispatchSync(ToggleNodeAction(k)),
      onMark: (k) => dispatchSync(MarkNodesAction.toggle(k)),
      onMarkRange: (k) => dispatchSync(MarkNodesAction.range(k, x.treeOrder)),
      onTreeFilter: (t) => dispatchSync(SetTreeFilterAction(t)),
      onPointFilter: (t) => dispatchSync(SetPointFilterAction(t)),
      onNoteLink: (w) => dispatch(GoAction.workspace(w.workspace)),
      onOpenMenu: (k) => dispatch(OpenNodeMenuAction(k)),
      onMenuShown: () => dispatchSync(CloseNodeMenuAction()),
      onMenuPick: (a) => dispatchSync(PickNodeActionAction(a)),
      onPoint: (k) => dispatch(SelectPointAction.toggle(k)),
      onCheck: (k) => dispatchSync(CheckPointsAction.toggle(k)),
      onRange: (k) => dispatchSync(CheckPointsAction.range(k, x.pointOrder)),
      onCheckAll: () => dispatchSync(CheckPointsAction.all(x.pointOrder)),
      onClear: () => dispatchSync(ClearSelectionAction()),
      onCopy: (keys) => dispatch(CopyKeysAction(keys)),
      onCopyValue: switch (x.pointValue) {
        final v? => () => dispatch(CopyValueAction(v)),
        null => null,
      },
      onToggleAssistant: () => dispatchSync(SetDrawerAction.toggle()),
      onTab: (t) => dispatch(OpenExplorerTabAction(t.tab)),
      onAction: (a) => dispatchSync(SetActionAction(a)),
      onHistoryRange: (r) => dispatch(PickHistoryRangeAction(r.range)),
      onTrendWindow: (w) => dispatchSync(ZoomHistoryAction(w.start, w.end)),
      onTrendReset: () => dispatchSync(SetHistoryWindowAction(null)),
      onCloseInspector: () => dispatchSync(SetActionAction(null)),
      onReadAgain: (key) => dispatch(RetryReadAction(key)),
      onTool: (t) => _onTool(x, t),
      onSetPoll: (s) => dispatchSync(StagePollAction(s)),
      onParam: (e) =>
          dispatchSync(StagePointEditAction(e.node, e.param, e.value)),
      onPanelWidth: (p) => dispatchSync(
        SetPanelWidthAction(WorkspacePanels.explorer.slot(p.side), p.width),
      ),
      onTapFlowEditor: (id) => dispatch(GoAction.push(FlowEditorRoute(id: id))),
      onViewPoint: switch (point) {
        final p? => () => dispatchSync(SetViewedPointAction(p)),
        null => null,
      },
      onCloseViewer: () => dispatchSync(SetViewedPointAction(null)),
    );
  }

  /// A tree row: its kind's icon, a link's mode and state.
  TreeRowVm _treeRow(ExplorerTreeRow r) => TreeRowVm(
    id: r.key,
    name: r.name,
    depth: r.depth,
    icon: AppIcon.nodeName(
      key: r.key,
      root: explorer.root,
      profile: r.info?.profile,
      value: r.info?.type != null,
    ),
    hasChildren: r.section || (r.info?.hasChildren ?? false),
    expanded: r.open,
    selected: r.selected,
    marked: r.marked,
    mode: r.mode?.tag,
    state: r.linkState?.node,
    count: r.count,
    hasHistory: r.info?.hasHistory ?? false,
    staged: r.staged,
    failed: r.fails.isEmpty ? null : FailChipVm.reads(r.fails.vm),
  );

  /// The points toolbar: Add point, Import, Apply profile.
  static List<ToolButtonVm> _toolbar(ExplorerView x) {
    final sel = x.selected!;
    return [
      ToolButtonVm(
        .addPoint,
        disabled: x.actionReach(sel, 'add_point').disabled(),
      ),
      ToolButtonVm(
        .importPoints,
        disabled: switch (x.actionReach(sel, x.importAction)) {
          NoSuchAction() => const NoAction('import'),
          final r => r.disabled(),
        },
      ),
      const ToolButtonVm(.applyProfile, disabled: NotThere(.profile)),
    ];
  }

  /// A header, toolbar or selection-bar button: one action each (the page
  /// runs Copy keys and Set poll itself; Apply profile and Record are
  /// disabled).
  Object? _onTool(ExplorerView x, ExplorerTool t) => switch ((x.selected, t)) {
    (null, _) => null,
    (final sel?, ExplorerTool.ping) => dispatch(InvokeNodeAction(sel, 'ping')),
    (_, ExplorerTool.addPoint) => dispatchSync(SetActionAction('add_point')),
    (_, ExplorerTool.importPoints) => dispatchSync(
      SetActionAction(x.importAction),
    ),
    (_, ExplorerTool.removeChecked) => dispatchSync(RemoveCheckedAction()),
    (
      _,
      ExplorerTool.copyKeys ||
          ExplorerTool.setPoll ||
          ExplorerTool.applyProfile ||
          ExplorerTool.record,
    ) =>
      null,
  };

  /// The inspector's form: an action staged (`config`) or run, or a new
  /// value of the point staged. A run waits for its answer: a refusal of
  /// the input goes back to the form (docs/design/specs/errors.md §3).
  FutureOr<FieldRefusal?> _submit(
    InspectorSubmit target,
    Map<String, Object?> values,
  ) {
    final args = plainArgs(values);
    switch (target) {
      case StageActionSubmit(:final key, :final action, :final display):
        dispatchSync(
          StageInvokeAction(
            key,
            action.name,
            args,
            display: display,
            keepEmpty: clearedNames(action.params),
          ),
        );
        return null;
      case RunActionSubmit(:final key, :final action):
        return sendForm(
          dispatchAndWait(
            InvokeNodeAction(
              key,
              action.name,
              args,
              clearedNames(action.params),
            ),
          ),
        );
      case StageValueSubmit(:final key):
        if (values.containsKey('value')) {
          dispatchSync(StageValueAction.entered(key, values['value']));
        }
        return null;
      case NoSubmit():
        return null;
    }
  }
}

/// What the page draws (compared) and what it starts (not compared).
class _Vm extends Vm {
  _Vm({
    required this.site,
    required this.tree,
    required this.treeLoading,
    required this.treeFilter,
    required this.watch,
    required this.keyName,
    required this.keyLinks,
    required this.title,
    required this.titleName,
    required this.pill,
    required this.subtitle,
    required this.headerButtons,
    required this.flowId,
    required this.flowDisabled,
    required this.tabs,
    required this.tab,
    required this.toolbar,
    required this.selectionBar,
    required this.pointFilter,
    required this.points,
    required this.pointsLoading,
    required this.pointsEmpty,
    required this.emptyButtons,
    required this.children,
    required this.params,
    required this.actionGroups,
    required this.result,
    required this.range,
    required this.trend,
    required this.historyRows,
    required this.historyNoPoint,
    required this.historyFailed,
    required this.auditRows,
    required this.auditNote,
    required this.inspector,
    required this.copyKeys,
    required this.pointValue,
    required this.menu,
    required this.menuOpening,
    required this.submit,
    required this.assistantOpen,
    required this.panelWidths,
    required this.viewer,
    required this.onShow,
    required this.onHide,
    required this.onSelect,
    required this.onToggle,
    required this.onMark,
    required this.onMarkRange,
    required this.onTreeFilter,
    required this.onPointFilter,
    required this.onNoteLink,
    required this.onOpenMenu,
    required this.onMenuShown,
    required this.onMenuPick,
    required this.onPoint,
    required this.onCheck,
    required this.onRange,
    required this.onCheckAll,
    required this.onClear,
    required this.onCopy,
    required this.onCopyValue,
    required this.onToggleAssistant,
    required this.onTab,
    required this.onAction,
    required this.onHistoryRange,
    required this.onTrendWindow,
    required this.onTrendReset,
    required this.onCloseInspector,
    required this.onReadAgain,
    required this.onTool,
    required this.onSetPoll,
    required this.onParam,
    required this.onPanelWidth,
    required this.onTapFlowEditor,
    required this.onViewPoint,
    required this.onCloseViewer,
  }) : super(
         equals: [
           site,
           tree,
           treeLoading,
           treeFilter,
           watch,
           keyName,
           keyLinks,
           title,
           titleName,
           pill,
           subtitle,
           headerButtons,
           flowId,
           flowDisabled,
           tabs,
           tab,
           toolbar,
           selectionBar,
           pointFilter,
           points,
           pointsLoading,
           pointsEmpty,
           emptyButtons,
           children,
           params,
           actionGroups,
           result,
           range,
           trend,
           historyRows,
           historyNoPoint,
           historyFailed,
           auditRows,
           auditNote,
           inspector,
           copyKeys,
           pointValue,
           menu,
           menuOpening,
           submit,
           assistantOpen,
           panelWidths,
           viewer,
           onCopyValue != null,
           onViewPoint != null,
         ],
       );

  final String site;
  final List<TreeRowVm> tree;
  final bool treeLoading;
  final String treeFilter;

  /// The keys on screen: a change watches them again.
  final List<String> watch;
  final String? keyName;
  final Set<String> keyLinks;
  final String? title;
  final String? titleName;
  final StatusPillVm? pill;
  final ExplorerSubtitleVm? subtitle;
  final List<ToolButtonVm> headerButtons;
  final String? flowId;
  final Disabled? flowDisabled;
  final List<ExplorerTabVm> tabs;
  final ExplorerTabTag tab;
  final List<ToolButtonVm> toolbar;
  final SelectionBarVm? selectionBar;
  final String pointFilter;
  final List<PointRowVm> points;
  final bool pointsLoading;
  final PointsEmpty? pointsEmpty;
  final List<ToolButtonVm> emptyButtons;
  final List<ChildRowVm> children;
  final List<ExplorerSectionVm> params;
  final List<ActionCardGroupVm> actionGroups;
  final ResultVm? result;
  final HistoryRangeTag range;
  final TrendVm? trend;
  final List<HistoryRowVm> historyRows;
  final bool historyNoPoint;
  final String? historyFailed;
  final List<AuditRowVm> auditRows;
  final AuditNote? auditNote;
  final ExplorerInspectorVm? inspector;
  final List<String> copyKeys;
  final String? pointValue;
  final ExplorerMenuVm? menu;
  final bool menuOpening;

  /// The inspector's form: whether it runs, what a submit does.
  final SubmitVm submit;

  /// The Assistant drawer is open over the page (⌘J).
  final bool assistantOpen;
  final SidePanelWidths panelWidths;
  final ValueViewerVm? viewer;

  final VoidCallback onShow;
  final VoidCallback onHide;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onToggle;
  final ValueChanged<String> onMark;
  final ValueChanged<String> onMarkRange;
  final ValueChanged<String> onTreeFilter;
  final ValueChanged<String> onPointFilter;
  final ValueChanged<NoteWorkspace> onNoteLink;
  final ValueChanged<String> onOpenMenu;
  final VoidCallback onMenuShown;
  final ValueChanged<String> onMenuPick;
  final ValueChanged<String> onPoint;
  final ValueChanged<String> onCheck;
  final ValueChanged<String> onRange;
  final VoidCallback onCheckAll;
  final VoidCallback onClear;
  final ValueChanged<List<String>> onCopy;
  final VoidCallback? onCopyValue;
  final VoidCallback onToggleAssistant;
  final ValueChanged<ExplorerTabTag> onTab;
  final ValueChanged<String> onAction;
  final ValueChanged<HistoryRangeTag> onHistoryRange;
  final ValueChanged<({int start, int end})> onTrendWindow;
  final VoidCallback onTrendReset;
  final VoidCallback onCloseInspector;
  final ValueChanged<String> onReadAgain;
  final ValueChanged<ExplorerTool> onTool;
  final ValueChanged<double> onSetPoll;
  final ValueChanged<ParamEdit> onParam;
  final ValueChanged<({PanelSide side, double width})> onPanelWidth;
  final ValueChanged<String> onTapFlowEditor;
  final VoidCallback? onViewPoint;
  final VoidCallback onCloseViewer;
}
