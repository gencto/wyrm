import 'package:business/common/memo.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/wyrm/explorer.dart';
import 'package:business/wyrm/keys.dart';
import 'package:equatable/equatable.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:ui/charts/trend.dart';
import 'package:ui/containers/action_card.dart';
import 'package:ui/containers/side_panels.dart';
import 'package:ui/indicators/fail_chip.dart';
import 'package:ui/indicators/node_state.dart';
import 'package:ui/indicators/status_pill.dart';
import 'package:ui/models/disabled.dart';
import 'package:ui/overlays/value_viewer.dart';
import 'package:ui/pages/explorer_page.dart';
import 'package:ui/tables/points_table.dart';
import 'package:ui/trees/tree_row.dart';

import '../common/side_panels.dart';
import 'explorer_mappers.dart';
import 'icon_mappers.dart';

/// Everything Explorer draws, as `ui` render models: what its connector
/// compares. Made by [explorerShownOf], which keeps the last one while
/// nothing it is made of changed.
final class ExplorerShown extends Equatable {
  const ExplorerShown({
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
    required this.point,
    required this.pointValue,
    required this.menu,
    required this.menuOpening,
    required this.busy,
    required this.assistantOpen,
    required this.panelWidths,
    required this.viewer,
  });

  final String site;
  final IList<TreeRowVm> tree;
  final bool treeLoading;
  final String treeFilter;

  /// The keys on screen: a change watches them again.
  final IList<String> watch;
  final String? keyName;
  final ISet<String> keyLinks;
  final String? title;
  final String? titleName;
  final StatusPillVm? pill;
  final ExplorerSubtitleVm? subtitle;
  final IList<ToolButtonVm> headerButtons;
  final String? flowId;
  final Disabled? flowDisabled;
  final IList<ExplorerTabVm> tabs;
  final ExplorerTabTag tab;
  final IList<ToolButtonVm> toolbar;
  final SelectionBarVm? selectionBar;
  final String pointFilter;
  final IList<PointRowVm> points;
  final bool pointsLoading;
  final PointsEmpty? pointsEmpty;
  final IList<ToolButtonVm> emptyButtons;
  final IList<ChildRowVm> children;
  final IList<ExplorerSectionVm> params;
  final IList<ActionCardGroupVm> actionGroups;
  final ResultVm? result;
  final HistoryRangeTag range;
  final TrendVm? trend;
  final IList<HistoryRowVm> historyRows;
  final bool historyNoPoint;
  final String? historyFailed;
  final IList<AuditRowVm> auditRows;
  final AuditNote? auditNote;
  final ExplorerInspectorVm? inspector;
  final IList<String> copyKeys;

  /// The point in the inspector: what *View value* opens.
  final String? point;

  /// What ⌘C copies: the value of [point].
  final String? pointValue;
  final ExplorerMenuVm? menu;
  final bool menuOpening;

  /// The inspector's form runs: a read or an apply is in flight.
  final bool busy;

  /// The Assistant drawer is open over the page (⌘J).
  final bool assistantOpen;
  final SidePanelWidths panelWidths;
  final ValueViewerVm? viewer;

  @override
  List<Object?> get props => [
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
    point,
    pointValue,
    menu,
    menuOpening,
    busy,
    assistantOpen,
    panelWidths,
    viewer,
  ];
}

final _tree = Memo<IList<TreeRowVm>>();
final _shown = Memo<ExplorerShown>();

/// What Explorer draws in [s]: made again only when a part of the state it
/// reads changed ([explorerInputsOf], the waits it shows, the drawer, the
/// panels, the language: a value viewer and a trend carry words of it);
/// its tree only when what the tree reads changed ([explorerTreeInputsOf]).
/// A dispatch elsewhere in the app, or a value of a key not on screen,
/// gives the very same object. Nothing here reads the clock.
ExplorerShown explorerShownOf(AppState s, Waiting w) {
  final r = _Read(s, w);
  final tree = _tree.of(
    explorerTreeInputsOf(s),
    () => [for (final row in r.explorer.treeRows) _treeRow(r, row)].lock,
  );
  final busy = r.waiting.nodes || r.waiting.applyChanges;
  final treeLoading = r.nodes.view.isEmpty && r.waiting.nodes;
  final menuOpening = r.waiting.nodeMenu;
  return _shown.of(
    [
      tree,
      ...explorerInputsOf(s, w),
      busy,
      treeLoading,
      menuOpening,
      s.assistant.drawer,
      s.panels.widths,
      s.language,
    ],
    () => _shownOf(
      r,
      tree,
      busy: busy,
      treeLoading: treeLoading,
      menuOpening: menuOpening,
    ),
  );
}

/// The state read through its selectors.
final class _Read with Selectors, WaitingGiven {
  _Read(this.state, this.given);

  @override
  final AppState state;

  @override
  final Waiting given;
}

ExplorerShown _shownOf(
  _Read r,
  IList<TreeRowVm> tree, {
  required bool busy,
  required bool treeLoading,
  required bool menuOpening,
}) {
  final x = r.explorer;
  final nodes = r.nodes;
  final sel = x.selected;
  final selection = x.selection;
  final answer = x.answer;
  final cards = x.actionCards;
  final history = x.history;
  final point = nodes.point;
  final toolbar = sel == null
      ? const IListConst<ToolButtonVm>([])
      : _toolbar(x);
  final name = sel?.split('/').last;
  return ExplorerShown(
    site: r.site.viewed ?? '',
    tree: tree,
    treeLoading: treeLoading,
    treeFilter: nodes.treeFilter,
    watch: x.watchKeys.lock,
    keyName: sel,
    keyLinks: parentLinksOf(sel, sections: explorerSections).lock,
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
      if (x.ping case final p?)
        ToolButtonVm(.ping, disabled: p.disabled(missing: .ping)),
    ].lock,
    flowId: x.flowId,
    flowDisabled: switch (x.flowEditor) {
      LacksLevel() => const NotThere(.readFlow),
      _ => null,
    },
    tabs: [for (final (t, n) in x.tabs) ExplorerTabVm(t.tag, count: n)].lock,
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
    points: [for (final p in x.pointRows) p.vm].lock,
    pointsLoading: x.pointsLoading,
    pointsEmpty: x.points.isNotEmpty
        ? null
        : (x.addsPoints ? PointsEmpty.noPointsYet : PointsEmpty.noPoints),
    emptyButtons: x.addsPoints
        ? toolbar.where((b) => b.tool != .applyProfile).toIList()
        : const IListConst([]),
    children: [for (final c in x.childRows) c.vm].lock,
    params: [for (final s in x.params) s.vm].lock,
    actionGroups: [
      for (final (staged, cards) in [(true, cards.staged), (false, cards.now)])
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
    ].lock,
    result: switch (answer) {
      final a? => ResultVm(
        action: a.title,
        count: a.answer.count,
        columns: a.columns,
        rows: [for (final row in a.answer.rows) row.unlock],
        lines: a.answer.lines.unlock,
      ),
      null => null,
    },
    range: nodes.historyRange.tag,
    trend: x.trend(reading: r.waiting.history)?.vm,
    historyRows: [
      for (final h in history?.rows ?? const <ExplorerHistoryRow>[])
        HistoryRowVm(time: h.time, value: h.value, mark: h.quality?.sample),
    ].lock,
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
    ].lock,
    auditNote: !x.canAudit
        ? AuditNote.needsRights
        : (nodes.audit.isEmpty ? AuditNote.none : null),
    inspector: x.inspector?.vm,
    copyKeys: x.copyKeys.lock,
    point: point,
    pointValue: x.pointValue,
    menu: x.menu?.vm,
    menuOpening: menuOpening,
    busy: busy,
    assistantOpen: r.assistant.drawer,
    panelWidths: WorkspacePanels.explorer.widths(r.panels.widths),
    viewer: x.viewer?.vm,
  );
}

/// A tree row: its kind's icon, a link's mode and state.
TreeRowVm _treeRow(_Read r, ExplorerTreeRow row) => TreeRowVm(
  id: row.key,
  name: row.name,
  depth: row.depth,
  icon: row.glyph.icon,
  hasChildren: row.section || (row.info?.hasChildren ?? false),
  expanded: row.open,
  selected: row.selected,
  marked: row.marked,
  mode: row.mode?.tag,
  state: row.linkState?.node,
  count: row.count,
  hasHistory: row.info?.hasHistory ?? false,
  staged: row.staged,
  failed: row.fails.isEmpty ? null : FailChipVm.reads(row.fails.vm),
);

/// The points toolbar: Add point, Import, Apply profile.
IList<ToolButtonVm> _toolbar(ExplorerView x) {
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
        final reach => reach.disabled(),
      },
    ),
    const ToolButtonVm(.applyProfile, disabled: NotThere(.profile)),
  ].lock;
}
