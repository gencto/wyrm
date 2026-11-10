import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

import '../buttons/button.dart';
import '../buttons/segmented_tabs.dart';
import '../charts/trend_chart.dart';
import '../containers/action_card.dart';
import '../containers/fault_boundary.dart';
import '../containers/inspector.dart';
import '../containers/inspector_sections.dart';
import '../containers/section_label.dart';
import '../containers/side_panels.dart';
import '../forms/action_form.dart';
import '../forms/param_form.dart';
import '../indicators/app_icon.dart';
import '../indicators/fail_chip.dart';
import '../indicators/key_line.dart';
import '../indicators/key_text.dart';
import '../indicators/quality_mark.dart';
import '../indicators/status_pill.dart';
import '../overlays/log_view.dart';
import '../overlays/value_viewer.dart';
import '../tables/points_table.dart';
import '../tables/row_table.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/typography.dart';
import '../trees/node_tree.dart';
import '../trees/tree_row.dart';

/// A group of action cards.
final class ActionCardGroupVm extends Equatable {
  const ActionCardGroupVm({
    required this.label,
    required this.note,
    required this.cards,
  });

  final String label;
  final String note;
  final List<ActionCardVm> cards;

  @override
  List<Object?> get props => [label, note, cards];
}

/// The answer of the last run of an action.
final class ResultVm extends Equatable {
  const ResultVm({
    required this.title,
    required this.status,
    this.columns = const [],
    this.rows = const [],
    this.lines = const [],
  });

  final String title;
  final String status;

  /// A table when the rows are records…
  final List<ColumnVm> columns;
  final List<RowVm> rows;

  /// …else the answer as JSON lines.
  final List<String> lines;

  @override
  List<Object?> get props => [title, status, columns, rows, lines];
}

/// A button of the header or the points toolbar: the node's own action, or
/// a control disabled with the reason.
final class ToolButtonVm extends Equatable {
  const ToolButtonVm({
    required this.id,
    required this.label,
    this.icon,
    this.quiet = false,
    this.disabledReason,
  });

  /// Handed back to `onTool`.
  final String id;
  final String label;
  final String? icon;

  /// A quieter outline (Import, Apply profile).
  final bool quiet;

  /// Null when the button works.
  final String? disabledReason;

  @override
  List<Object?> get props => [id, label, icon, quiet, disabledReason];
}

/// What the inspector shows: a point, an action's form, or the node on
/// screen.
sealed class ExplorerInspectorVm extends Equatable {
  const ExplorerInspectorVm();
}

/// A point (docs/design/specs/explorer.md §4): its name and display name,
/// its value and quality, then sections built from its `~meta.cfg`.
final class PointInspectorVm extends ExplorerInspectorVm {
  const PointInspectorVm({
    required this.eyebrow,
    required this.name,
    required this.value,
    required this.quality,
    required this.sections,
    this.display,
    this.edit,
    this.editLabel = '',
    this.stageLabel = '',
    this.readOnlyReason,
  });

  /// `Point`.
  final String eyebrow;
  final String name;
  final String? display;

  /// The value with its unit.
  final String value;
  final QualityMarkVm quality;
  final List<InspectorSectionVm> sections;

  /// The field that stages a new value; null when the point cannot be set.
  final ParamFieldVm? edit;
  final String editLabel;
  final String stageLabel;
  final String? readOnlyReason;

  @override
  List<Object?> get props => [
    eyebrow,
    name,
    display,
    value,
    quality,
    sections,
    edit,
    editLabel,
    stageLabel,
    readOnlyReason,
  ];
}

/// An action: its form, Run now or Stage, the CLI line.
final class ActionInspectorVm extends ExplorerInspectorVm {
  const ActionInspectorVm({
    required this.id,
    required this.eyebrow,
    required this.title,
    required this.keyName,
    required this.tags,
    required this.fields,
    required this.submit,
    required this.cli,
    required this.cliLabel,
    required this.note,
    this.disabledReason,
  });

  final String id;

  /// `Action`.
  final String eyebrow;
  final String title;
  final String keyName;

  /// `runs now`, `needs read`, `returns rows`.
  final List<String> tags;
  final List<ParamFieldVm> fields;

  /// `Run now` or `Stage`.
  final String submit;
  final String cli;
  final String cliLabel;
  final String note;
  final String? disabledReason;

  @override
  List<Object?> get props => [
    id,
    eyebrow,
    title,
    keyName,
    tags,
    fields,
    submit,
    cli,
    cliLabel,
    note,
    disabledReason,
  ];
}

/// The node on screen with no point selected (§4 "nothing selected"): its
/// parameters as a form from `cfg`, then its diagnostics.
final class NodeInspectorVm extends ExplorerInspectorVm {
  const NodeInspectorVm({
    required this.eyebrow,
    required this.title,
    required this.sections,
  });

  /// `Device`, `Connection`, `Link`.
  final String eyebrow;
  final String title;
  final List<InspectorSectionVm> sections;

  @override
  List<Object?> get props => [eyebrow, title, sections];
}

/// The bar that replaces the points toolbar while 2 or more rows are
/// checked (§6): `<n> selected`, its buttons, Clear.
final class SelectionBarVm extends Equatable {
  const SelectionBarVm({
    required this.count,
    required this.buttons,
    required this.clear,
  });

  /// `3 selected`.
  final String count;
  final List<ToolButtonVm> buttons;
  final String clear;

  @override
  List<Object?> get props => [count, buttons, clear];
}

/// Board *Studio · Explorer* (docs/design/specs/explorer.md): the tree, the
/// node on screen with its key line, title, tabs and points, and the
/// inspector of the point, action or node.
class ExplorerPage extends StatelessWidget {
  const ExplorerPage({
    required this.treeLabel,
    required this.tree,
    required this.onTap,
    required this.onToggle,
    required this.tabs,
    required this.tab,
    required this.onTab,
    required this.onTapFlowEditor,
    this.onMenu,
    this.onMark,
    this.onMarkRange,
    this.treeFilter = '',
    this.onTreeFilter,
    this.treeFilterHint = '',
    this.treeNote,
    this.onNoteLink,
    this.treeLoading = false,
    this.keyName,
    this.onCopyKey,
    this.copyKeyLabel = 'Copy key',
    this.title,
    this.pill,
    this.subtitle,
    this.headerButtons = const [],
    this.openButton,
    this.actionsLabel,
    this.onActions,
    this.onTool,
    this.empty = '',
    this.toolbar = const [],
    this.selectionBar,
    this.onClearSelection,
    this.pointFilter = '',
    this.onPointFilter,
    this.pointFilterHint = '',
    this.points = const [],
    this.pointLabels = const PointsTableLabels(),
    this.pointsLoading = false,
    this.pointsNote,
    this.pointsEmpty,
    this.emptyButtons = const [],
    this.childColumns = const [],
    this.children = const [],
    this.childrenEmpty,
    this.childrenNote,
    this.onChild,
    this.onPoint,
    this.onCheck,
    this.onRange,
    this.onCheckAll,
    this.params = const [],
    this.paramsNote,
    this.actionGroups = const [],
    this.onAction,
    this.result,
    this.ranges = const [],
    this.range = '',
    this.onHistoryRange,
    this.trend = const [],
    this.trendLabels = const ('', ''),
    this.trendEmpty = '',
    this.historyColumns = const [],
    this.historyRows = const [],
    this.historyNote,
    this.historyFail,
    this.auditColumns = const [],
    this.auditRows = const [],
    this.auditNote,
    this.inspector,
    this.onSubmit,
    this.onCloseInspector,
    this.busy = false,
    this.panels = const SidePanelWidths(),
    this.onPanelWidth,
    this.viewer,
    this.onViewPoint,
    this.onCloseViewer,
    this.viewLabel = 'View value',
    this.copyLabel = 'Copy',
    this.copiedLabel = 'Copied',
    this.closeLabel = 'Close',
    super.key,
  });

  final String treeLabel;
  final List<TreeRowVm> tree;
  final ValueChanged<String> onTap;
  final ValueChanged<String> onToggle;
  final void Function(String id, Offset at)? onMenu;
  final ValueChanged<String>? onMark;
  final ValueChanged<String>? onMarkRange;
  final String treeFilter;
  final ValueChanged<String>? onTreeFilter;
  final String treeFilterHint;
  final TreeNoteVm? treeNote;
  final ValueChanged<String>? onNoteLink;
  final bool treeLoading;

  final String? keyName;
  final VoidCallback? onCopyKey;
  final String copyKeyLabel;
  final String? title;
  final StatusPillVm? pill;

  /// `modbus device · unit 1 · 127.0.0.1:5020 · last read 12:00:03`.
  final String? subtitle;

  /// Ping, beside Actions ▾.
  final List<ToolButtonVm> headerButtons;

  /// A button that opens another screen on this node (a flow's Edit
  /// dataflow): its id goes to [onTapFlowEditor].
  final ToolButtonVm? openButton;

  /// Opens the flow editor on a flow id.
  final void Function(String) onTapFlowEditor;

  /// `Actions`: the node menu, opened at a point.
  final String? actionsLabel;
  final ValueChanged<Offset>? onActions;

  /// A header, toolbar, empty-state or selection-bar button, by its id.
  final ValueChanged<String>? onTool;

  /// Shown when nothing is selected.
  final String empty;
  final List<TabItemVm> tabs;
  final String tab;
  final ValueChanged<String> onTab;

  final List<ToolButtonVm> toolbar;
  final SelectionBarVm? selectionBar;
  final VoidCallback? onClearSelection;
  final String pointFilter;
  final ValueChanged<String>? onPointFilter;
  final String pointFilterHint;
  final List<PointRowVm> points;
  final PointsTableLabels pointLabels;
  final bool pointsLoading;
  final String? pointsNote;

  /// `No points yet`, with [emptyButtons] under it.
  final String? pointsEmpty;
  final List<ToolButtonVm> emptyButtons;

  /// The `children` tab of a node that is not a device (a link, a
  /// connection, a folder, a broker, storage): its children as rows.
  final List<ColumnVm> childColumns;
  final List<RowVm> children;
  final String? childrenEmpty;
  final String? childrenNote;

  /// A child row tapped: its key.
  final ValueChanged<String>? onChild;
  final ValueChanged<String>? onPoint;
  final ValueChanged<String>? onCheck;
  final ValueChanged<String>? onRange;
  final VoidCallback? onCheckAll;

  final List<InspectorSectionVm> params;
  final String? paramsNote;

  final List<ActionCardGroupVm> actionGroups;
  final ValueChanged<String>? onAction;
  final ResultVm? result;

  final List<TabItemVm> ranges;
  final String range;
  final ValueChanged<String>? onHistoryRange;
  final List<TrendSeriesVm> trend;
  final (String, String) trendLabels;
  final String trendEmpty;
  final List<ColumnVm> historyColumns;
  final List<RowVm> historyRows;

  /// Why there is no history here (a node, not a point).
  final String? historyNote;

  /// Reading the history failed: the chip over the chart (`history
  /// unavailable`, docs/design/specs/errors.md §4).
  final FailChipVm? historyFail;

  final List<ColumnVm> auditColumns;
  final List<RowVm> auditRows;

  /// Why the audit is empty or cannot be read.
  final String? auditNote;

  final ExplorerInspectorVm? inspector;
  final ValueChanged<Map<String, Object?>>? onSubmit;

  /// Closes an action's form (the point and node inspectors have no close:
  /// they are part of the layout).
  final VoidCallback? onCloseInspector;
  final bool busy;

  /// The tree and inspector widths the viewer chose (§1).
  final SidePanelWidths panels;
  final void Function(PanelSide side, double width)? onPanelWidth;

  /// The open value viewer of a point, live; null: none is open.
  final ValueViewerVm? viewer;

  /// The eye beside the point inspector's value: opens the viewer.
  final VoidCallback? onViewPoint;
  final VoidCallback? onCloseViewer;
  final String viewLabel;
  final String copyLabel;
  final String copiedLabel;
  final String closeLabel;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final wide = box.maxWidth >= 1100;
      final treePanel = NodeTree(
        label: treeLabel,
        rows: tree,
        onTap: onTap,
        onToggle: onToggle,
        onMenu: onMenu,
        onMark: onMark,
        onMarkRange: onMarkRange,
        filter: treeFilter,
        onFilter: onTreeFilter,
        filterHint: treeFilterHint,
        note: treeNote,
        onNoteLink: onNoteLink,
        loading: treeLoading,
        width: wide ? 260 : 240,
      );
      final ins = inspector;
      // One stack whether a viewer is open or not, so the panels keep
      // their state when it opens.
      return Stack(
        children: [
          Positioned.fill(child: _panels(context, box, treePanel, ins)),
          if (viewer case final v?)
            Positioned.fill(
              child: ValueViewer(
                key: const ValueKey('value-viewer'),
                vm: v,
                onClose: onCloseViewer ?? () {},
                copyLabel: copyLabel,
                copiedLabel: copiedLabel,
                closeLabel: closeLabel,
              ),
            ),
        ],
      );
    },
  );

  Widget _panels(
    BuildContext context,
    BoxConstraints box,
    Widget treePanel,
    ExplorerInspectorVm? ins,
  ) {
    final wide = box.maxWidth >= 1100;
    return SidePanels(
      left: box.maxWidth >= 700
          ? SidePanel(
              width: panels.left,
              defaultWidth: wide ? 260 : 240,
              child: FaultBoundary(
                panel: .tree,
                child: treePanel,
              ),
            )
          : null,
      center: FaultBoundary(
        panel: .workspace,
        child: _workspace(context),
      ),
      right: ins != null && wide
          ? SidePanel(
              width: panels.right,
              defaultWidth: 320,
              child: FaultBoundary(
                panel: .inspector,
                child: _inspector(context, ins),
              ),
            )
          : null,
      onChanged: onPanelWidth,
    );
  }

  Widget _button(ToolButtonVm b) {
    final onPressed = b.disabledReason != null || onTool == null
        ? null
        : () => onTool!(b.id);
    return b.quiet
        ? Button.quiet(
            label: b.label,
            icon: b.icon,
            onPressed: onPressed,
            disabledReason: b.disabledReason,
          )
        : Button.secondary(
            label: b.label,
            icon: b.icon,
            onPressed: onPressed,
            disabledReason: b.disabledReason,
          );
  }

  Widget _workspace(BuildContext context) {
    final c = context.colors;
    if (title == null) {
      return Center(
        child: Text(empty, style: TextStyle(fontSize: 14, color: c.text4)),
      );
    }
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      child: Column(
        crossAxisAlignment: .stretch,
        spacing: 14,
        children: [
          if (keyName case final k?)
            KeyLine(keyName: k, onCopy: onCopyKey, copyLabel: copyKeyLabel),
          LayoutBuilder(
            // The name and the subtitle take what the buttons leave and
            // end in an ellipsis; under 560 the buttons go below them.
            builder: (context, box) {
              final heading = _heading(c, title!);
              final buttons = _headerButtons(c);
              return box.maxWidth < 560
                  ? Column(
                      crossAxisAlignment: .start,
                      spacing: 12,
                      children: [heading, buttons],
                    )
                  : Row(
                      crossAxisAlignment: .end,
                      spacing: 16,
                      children: [
                        Expanded(child: heading),
                        buttons,
                      ],
                    );
            },
          ),
          SegmentedTabs(
            tabs: tabs,
            selected: tab,
            onSelect: onTab,
            plainCounts: true,
            height: 44,
          ),
        ],
      ),
    );
    final body = switch (tab) {
      'params' => _padded([
        if (paramsNote case final n?)
          Text(n, style: TextStyle(fontSize: 13, color: c.text3)),
        InspectorSections(sections: params),
      ]),
      'actions' => _padded(_actions(c)),
      'history' => _padded([
        if (historyNote case final n?)
          Text(n, style: TextStyle(fontSize: 13, color: c.text4))
        else ...[
          if (historyFail case final f?)
            Align(
              alignment: .centerLeft,
              child: FailChip(vm: f),
            ),
          SegmentedTabs(
            tabs: ranges,
            selected: range,
            onSelect: onHistoryRange ?? (_) {},
          ),
          TrendChart(series: trend, empty: trendEmpty, timeLabels: trendLabels),
          if (historyRows.isNotEmpty)
            RowTable(columns: historyColumns, rows: historyRows, rowHeight: 40),
        ],
      ]),
      'audit' => _padded([
        if (auditNote case final n?)
          Text(n, style: TextStyle(fontSize: 13, color: c.text4)),
        if (auditRows.isNotEmpty)
          RowTable(columns: auditColumns, rows: auditRows, rowHeight: 40),
      ]),
      'children' => _padded([
        RowTable(
          columns: childColumns,
          rows: children,
          rowHeight: 48,
          onTap: onChild,
          empty: childrenEmpty,
        ),
        if (childrenNote case final n?)
          Text(n, style: TextStyle(fontSize: 13, color: c.text4)),
      ]),
      'points' => _pointsTab(c),
      _ => const SizedBox.shrink(),
    };
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [header, body],
    );
  }

  /// The node's name in mono 26 with its state pill, and one subtitle line
  /// under it: both one line with an ellipsis, the full text as a tooltip
  /// (a display name can be a sentence).
  Widget _heading(AppColors c, String name) => Column(
    crossAxisAlignment: .start,
    mainAxisSize: .min,
    spacing: 6,
    children: [
      Row(
        spacing: 12,
        children: [
          Flexible(
            child: Tooltip(
              message: name,
              waitDuration: const Duration(milliseconds: 600),
              child: Text(
                name,
                maxLines: 1,
                overflow: .ellipsis,
                style: mono(size: 26, weight: .w600, color: c.text1),
              ),
            ),
          ),
          if (pill case final p?) StatusPill(vm: p, dense: true),
        ],
      ),
      if (subtitle case final s?)
        Tooltip(
          message: s,
          waitDuration: const Duration(milliseconds: 600),
          child: Text(
            s,
            maxLines: 1,
            overflow: .ellipsis,
            style: TextStyle(fontSize: 14, color: c.text3),
          ),
        ),
    ],
  );

  /// Edit dataflow, Ping, Actions ▾.
  Widget _headerButtons(AppColors c) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      if (openButton case final o?)
        Button.secondary(
          label: o.label,
          icon: o.icon,
          onPressed: o.disabledReason == null
              ? () => onTapFlowEditor(o.id)
              : null,
          disabledReason: o.disabledReason,
        ),
      for (final b in headerButtons) _button(b),
      if (actionsLabel case final a?)
        Builder(
          builder: (context) => _actionsButton(
            c,
            label: a,
            onTap: onActions == null
                ? null
                : () {
                    final box = context.findRenderObject()! as RenderBox;
                    onActions!(
                      box.localToGlobal(
                        Offset(box.size.width - 300, box.size.height + 6),
                      ),
                    );
                  },
          ),
        ),
    ],
  );

  Widget _padded(List<Widget> children) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
    child: Column(
      crossAxisAlignment: .stretch,
      spacing: 16,
      children: children,
    ),
  );

  Widget _pointsTab(AppColors c) {
    final bar = selectionBar;
    final toolbarRow = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: SizedBox(
        height: 40,
        child: bar != null
            ? Row(
                spacing: 8,
                children: [
                  Text(
                    bar.count,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: .w600,
                      color: c.text1,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: .horizontal,
                      child: Row(
                        spacing: 8,
                        children: [for (final b in bar.buttons) _button(b)],
                      ),
                    ),
                  ),
                  Button.quiet(label: bar.clear, onPressed: onClearSelection),
                ],
              )
            : LayoutBuilder(
                // The filter takes up to 240 and gives way first; the
                // buttons scroll only when even a 160 filter leaves them
                // too little room.
                builder: (context, box) => Row(
                  spacing: 8,
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: .horizontal,
                        child: Row(
                          spacing: 8,
                          children: [
                            for (final b in toolbar)
                              if (b.quiet) _button(b) else _filled(c, b),
                          ],
                        ),
                      ),
                    ),
                    if (onPointFilter != null)
                      SizedBox(
                        width: (box.maxWidth - 500).clamp(160, 240),
                        child: _filterBox(c),
                      ),
                  ],
                ),
              ),
      ),
    );
    final showEmpty = !pointsLoading && points.isEmpty && pointsEmpty != null;
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        toolbarRow,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: showEmpty
              ? _empty(c)
              : PointsTable(
                  rows: points,
                  labels: pointLabels,
                  loading: pointsLoading,
                  onTap: onPoint,
                  onCheck: onCheck,
                  onRange: onRange,
                  onCheckAll: onCheckAll,
                ),
        ),
        if (pointsNote case final n?)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
            child: Text(n, style: TextStyle(fontSize: 13, color: c.text4)),
          ),
      ],
    );
  }

  /// Add point: an outline on the raised ground.
  Widget _filled(AppColors c, ToolButtonVm b) => DecoratedBox(
    decoration: BoxDecoration(color: c.ground2, borderRadius: Radii.button),
    child: _button(b),
  );

  Widget _filterBox(AppColors c) => Container(
    height: 40,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(
      color: c.ground1,
      border: .all(color: c.line1),
      borderRadius: Radii.button,
    ),
    child: Row(
      spacing: 8,
      children: [
        AppIcon('ui_search', size: 14, color: c.text4),
        Expanded(
          child: TextFormField(
            initialValue: pointFilter,
            onChanged: onPointFilter,
            style: TextStyle(fontSize: 13, color: c.text1),
            decoration: InputDecoration(
              isCollapsed: true,
              contentPadding: EdgeInsets.zero,
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              hintText: pointFilterHint,
              hintStyle: TextStyle(fontSize: 13, color: c.text4),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _empty(AppColors c) => Container(
    padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
    decoration: BoxDecoration(
      color: c.ground1,
      border: .all(color: c.line1),
      borderRadius: Radii.card,
    ),
    child: Column(
      spacing: 16,
      children: [
        Text(
          pointsEmpty!,
          style: TextStyle(fontSize: 16, fontWeight: .w600, color: c.text1),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: .center,
          children: [for (final b in emptyButtons) _button(b)],
        ),
      ],
    ),
  );

  List<Widget> _actions(AppColors c) => [
    for (final g in actionGroups)
      Column(
        crossAxisAlignment: .stretch,
        spacing: 10,
        children: [
          Column(
            crossAxisAlignment: .stretch,
            spacing: 4,
            children: [
              SectionLabel(g.label),
              Text(g.note, style: TextStyle(fontSize: 12, color: c.text4)),
            ],
          ),
          LayoutBuilder(
            builder: (context, box) {
              final n = box.maxWidth > 640 ? 2 : 1;
              final w = (box.maxWidth - 12 * (n - 1)) / n;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final card in g.cards)
                    SizedBox(
                      width: w,
                      child: ActionCard(vm: card, onTap: onAction),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    if (result case final r?) ...[
      Row(
        spacing: 12,
        children: [
          Text(
            r.title,
            style: const TextStyle(fontSize: 14, fontWeight: .w600),
          ),
          QualityMark(
            vm: QualityMarkVm(label: r.status, tone: .good),
          ),
        ],
      ),
      if (r.rows.isNotEmpty)
        RowTable(columns: r.columns, rows: r.rows)
      else
        SizedBox(height: 260, child: LogView(lines: r.lines)),
    ],
  ];

  Widget _inspector(BuildContext context, ExplorerInspectorVm ins) {
    final c = context.colors;
    return switch (ins) {
      PointInspectorVm() => Inspector(
        eyebrow: ins.eyebrow,
        title: '',
        width: 320,
        header: Column(
          crossAxisAlignment: .start,
          spacing: 10,
          children: [
            Row(
              crossAxisAlignment: .baseline,
              textBaseline: .alphabetic,
              spacing: 10,
              children: [
                Flexible(
                  child: Text(
                    ins.name,
                    maxLines: 1,
                    overflow: .ellipsis,
                    style: mono(size: 18, weight: .w600),
                  ),
                ),
                if (ins.display case final d?)
                  Flexible(
                    child: Text(
                      d,
                      maxLines: 1,
                      overflow: .ellipsis,
                      style: TextStyle(fontSize: 14, color: c.text3),
                    ),
                  ),
              ],
            ),
            Row(
              spacing: 10,
              children: [
                Flexible(
                  child: Text(
                    ins.value,
                    maxLines: 1,
                    overflow: .ellipsis,
                    style: mono(size: 22, color: c.text1),
                  ),
                ),
                QualityMark(vm: ins.quality, size: 12),
                if (onViewPoint case final view?)
                  IconButton(
                    tooltip: viewLabel,
                    visualDensity: .compact,
                    onPressed: view,
                    icon: AppIcon('ui_view', size: 16, color: c.text3),
                  ),
              ],
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: .stretch,
          spacing: 18,
          children: [
            InspectorSections(sections: ins.sections),
            if (ins.edit case final e?) ...[
              SectionLabel(ins.editLabel),
              ActionForm(
                key: ValueKey('set:${ins.name}'),
                fields: [e],
                submit: ins.stageLabel,
                busy: busy,
                disabledReason: ins.readOnlyReason,
                onSubmit: onSubmit ?? (_) {},
              ),
            ],
          ],
        ),
      ),
      ActionInspectorVm() => Inspector(
        eyebrow: ins.eyebrow,
        title: ins.title,
        width: 320,
        onClose: onCloseInspector,
        header: Column(
          crossAxisAlignment: .start,
          spacing: 8,
          children: [
            KeyText(ins.keyName, size: 12, color: c.text3),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final t in ins.tags)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: c.ground4,
                      borderRadius: Radii.chip,
                    ),
                    child: Text(t, style: mono(size: 11, color: c.text2)),
                  ),
              ],
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: .stretch,
          spacing: 16,
          children: [
            ActionForm(
              key: ValueKey(ins.id),
              fields: ins.fields,
              submit: ins.submit,
              busy: busy,
              disabledReason: ins.disabledReason,
              onSubmit: onSubmit ?? (_) {},
            ),
            Text(
              ins.note,
              style: TextStyle(fontSize: 12, height: 1.5, color: c.text3),
            ),
            SectionLabel(ins.cliLabel),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: c.ground0,
                border: .all(color: c.line1),
                borderRadius: Radii.button,
              ),
              child: SelectableText(
                ins.cli,
                style: mono(size: 12, color: c.text2),
              ),
            ),
          ],
        ),
      ),
      NodeInspectorVm() => Inspector(
        eyebrow: ins.eyebrow,
        title: ins.title,
        width: 320,
        child: InspectorSections(sections: ins.sections),
      ),
    };
  }

  /// Actions ▾: an outline 40 with a chevron.
  Widget _actionsButton(
    AppColors c, {
    required String label,
    VoidCallback? onTap,
  }) => Material(
    color: Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: Radii.button,
      side: BorderSide(color: c.line3),
    ),
    child: InkWell(
      onTap: onTap,
      borderRadius: Radii.button,
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          mainAxisSize: .min,
          spacing: 8,
          children: [
            Text(label, style: TextStyle(fontSize: 14, color: c.text1)),
            AppIcon('ui_chevron_down', size: 14, color: c.text1),
          ],
        ),
      ),
    ),
  );
}
