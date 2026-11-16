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
import 'package:business/redux/nodes/actions/mark_nodes_action.dart';
import 'package:business/redux/nodes/actions/open_explorer_tab_action.dart';
import 'package:business/redux/nodes/actions/open_node_menu_action.dart';
import 'package:business/redux/nodes/actions/pick_history_range_action.dart';
import 'package:business/redux/nodes/actions/pick_node_action_action.dart';
import 'package:business/redux/nodes/actions/retry_read_action.dart';
import 'package:business/redux/nodes/actions/rewatch_explorer_action.dart';
import 'package:business/redux/nodes/actions/run_explorer_command_action.dart';
import 'package:business/redux/nodes/actions/select_node_action.dart';
import 'package:business/redux/nodes/actions/select_point_action.dart';
import 'package:business/redux/nodes/actions/set_action_action.dart';
import 'package:business/redux/nodes/actions/set_history_window_action.dart';
import 'package:business/redux/nodes/actions/set_point_filter_action.dart';
import 'package:business/redux/nodes/actions/set_tree_filter_action.dart';
import 'package:business/redux/nodes/actions/set_viewed_point_action.dart';
import 'package:business/redux/nodes/actions/show_explorer_action.dart';
import 'package:business/redux/nodes/actions/stage_point_edit_action.dart';
import 'package:business/redux/nodes/actions/stage_poll_action.dart';
import 'package:business/redux/nodes/actions/submit_inspector_action.dart';
import 'package:business/redux/nodes/actions/toggle_node_action.dart';
import 'package:business/redux/nodes/actions/zoom_history_action.dart';
import 'package:business/redux/panels/actions/set_panel_width_action.dart';
import 'package:business/wyrm/explorer.dart' show explorerPolls;
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/containers/side_panels.dart';
import 'package:ui/models/submit.dart';
import 'package:ui/pages/explorer_page.dart';

import '../common/forms.dart';
import '../common/side_panels.dart';
import '../common/tab_visibility.dart';
import '../common/value_viewer.dart';
import '../mappers/explorer_mappers.dart';
import '../mappers/explorer_shown.dart';
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
      if (!_sameKeys(before.shown.watch, now.shown.watch)) {
        store.dispatchSync(RewatchExplorerAction());
      }
    },
    builder: (_, vm) => TabVisibility(
      onShow: vm.onShow,
      onHide: vm.onHide,
      child: ExplorerPage(
        site: vm.shown.site,
        tree: vm.shown.tree.unlockView,
        treeLoading: vm.shown.treeLoading,
        treeFilter: vm.shown.treeFilter,
        onTreeFilter: vm.onTreeFilter,
        onNoteLink: vm.onNoteLink,
        onTap: vm.onSelect,
        onToggle: vm.onToggle,
        onMark: vm.onMark,
        onMarkRange: vm.onMarkRange,
        onOpenMenu: vm.onOpenMenu,
        menu: vm.shown.menu,
        menuOpening: vm.shown.menuOpening,
        onMenuShown: vm.onMenuShown,
        onMenuPick: vm.onMenuPick,
        keyName: vm.shown.keyName,
        keyLinks: vm.shown.keyLinks.unlockView,
        copyKeys: vm.shown.copyKeys.unlockView,
        onCopy: vm.onCopy,
        onCopyValue: vm.onCopyValue,
        onClear: vm.onClear,
        onToggleAssistant: vm.onToggleAssistant,
        title: vm.shown.title,
        titleName: vm.shown.titleName,
        pill: vm.shown.pill,
        subtitle: vm.shown.subtitle,
        headerButtons: vm.shown.headerButtons.unlockView,
        flowId: vm.shown.flowId,
        flowDisabled: vm.shown.flowDisabled,
        onTapFlowEditor: vm.onTapFlowEditor,
        onTool: vm.onTool,
        tabs: vm.shown.tabs.unlockView,
        tab: vm.shown.tab,
        onTab: vm.onTab,
        toolbar: vm.shown.toolbar.unlockView,
        selectionBar: vm.shown.selectionBar,
        polls: explorerPolls,
        onSetPoll: vm.onSetPoll,
        pointFilter: vm.shown.pointFilter,
        onPointFilter: vm.onPointFilter,
        points: vm.shown.points.unlockView,
        pointsLoading: vm.shown.pointsLoading,
        pointsEmpty: vm.shown.pointsEmpty,
        emptyButtons: vm.shown.emptyButtons.unlockView,
        children: vm.shown.children.unlockView,
        onChild: vm.onSelect,
        onPoint: vm.onPoint,
        onCheck: vm.onCheck,
        onRange: vm.onRange,
        onCheckAll: vm.onCheckAll,
        params: vm.shown.params.unlockView,
        onParam: vm.onParam,
        actionGroups: vm.shown.actionGroups.unlockView,
        onAction: vm.onAction,
        result: vm.shown.result,
        range: vm.shown.range,
        onHistoryRange: vm.onHistoryRange,
        trend: vm.shown.trend,
        onTrendWindow: (a, b) => vm.onTrendWindow((start: a, end: b)),
        onTrendReset: vm.onTrendReset,
        historyRows: vm.shown.historyRows.unlockView,
        historyNoPoint: vm.shown.historyNoPoint,
        historyFailed: vm.shown.historyFailed,
        auditRows: vm.shown.auditRows.unlockView,
        auditNote: vm.shown.auditNote,
        inspector: vm.shown.inspector,
        submit: vm.submit,
        onReadAgain: vm.onReadAgain,
        onCloseInspector: vm.onCloseInspector,
        panels: vm.shown.panelWidths,
        onPanelWidth: (side, w) => vm.onPanelWidth((side: side, width: w)),
        viewer: vm.shown.viewer,
        viewerTables: viewerTables,
        onViewPoint: vm.onViewPoint,
        onCloseViewer: vm.onCloseViewer,
        drawer: vm.shown.assistantOpen
            ? const AssistantDrawerConnector()
            : null,
      ),
    ),
  );

  static bool _sameKeys(IList<String> a, IList<String> b) =>
      a.length == b.length && a.every(b.contains);
}

/// Factory that creates a view-model for the StoreConnector.
class _Factory extends VmFactory<AppState, ExplorerPageConnector, _Vm>
    with Selectors {
  _Factory(super._connector);

  /// What is drawn comes from [explorerShownOf], the same object while
  /// nothing it shows changed; each callback names what was done, and an
  /// action reads the rest (the rows on screen, the inspector's target)
  /// when it runs.
  @override
  _Vm fromStore() {
    final shown = explorerShownOf(state);
    return _Vm(
      shown: shown,
      submit: SubmitVm(
        busy: shown.busy,
        onSubmit: (values) => sendForm(
          dispatchAndWait(SubmitInspectorAction(plainArgs(values))),
        ),
      ),
      onShow: () => dispatch(ShowExplorerAction()),
      onHide: () => dispatchSync(HideExplorerAction()),
      onSelect: (k) => dispatch(SelectNodeAction(k)),
      onToggle: (k) => dispatchSync(ToggleNodeAction(k)),
      onMark: (k) => dispatchSync(MarkNodesAction.toggle(k)),
      onMarkRange: (k) => dispatchSync(MarkNodesAction.range(k)),
      onTreeFilter: (t) => dispatchSync(SetTreeFilterAction(t)),
      onPointFilter: (t) => dispatchSync(SetPointFilterAction(t)),
      onNoteLink: (w) => dispatch(GoAction.workspace(w.workspace)),
      onOpenMenu: (k) => dispatch(OpenNodeMenuAction(k)),
      onMenuShown: () => dispatchSync(CloseNodeMenuAction()),
      onMenuPick: (a) => dispatchSync(PickNodeActionAction(a)),
      onPoint: (k) => dispatch(SelectPointAction.toggle(k)),
      onCheck: (k) => dispatchSync(CheckPointsAction.toggle(k)),
      onRange: (k) => dispatchSync(CheckPointsAction.range(k)),
      onCheckAll: () => dispatchSync(CheckPointsAction.all()),
      onClear: () => dispatchSync(ClearSelectionAction()),
      onCopy: (keys) => dispatch(CopyKeysAction(keys)),
      // keyed by `shown.pointValue`, which the view-model compares
      onCopyValue: switch (shown.pointValue) {
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
      onTool: (t) => switch (t.command) {
        final c? => dispatch(RunExplorerCommandAction(c)),
        null => null,
      },
      onSetPoll: (s) => dispatchSync(StagePollAction(s)),
      onParam: (e) =>
          dispatchSync(StagePointEditAction(e.node, e.param, e.value)),
      onPanelWidth: (p) => dispatchSync(
        SetPanelWidthAction(WorkspacePanels.explorer.slot(p.side), p.width),
      ),
      onTapFlowEditor: (id) => dispatch(GoAction.push(FlowEditorRoute(id: id))),
      // keyed by `shown.point`, which the view-model compares
      onViewPoint: switch (shown.point) {
        final p? => () => dispatchSync(SetViewedPointAction(p)),
        null => null,
      },
      onCloseViewer: () => dispatchSync(SetViewedPointAction(null)),
    );
  }
}

/// What the page draws ([shown] and the form's [submit], compared) and what
/// it starts (not compared).
class _Vm extends Vm {
  _Vm({
    required this.shown,
    required this.submit,
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
  }) : super(equals: [shown, submit]);

  /// Everything drawn, as `ui` render models.
  final ExplorerShown shown;

  /// The inspector's form: whether it runs, what a submit does.
  final SubmitVm submit;

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
