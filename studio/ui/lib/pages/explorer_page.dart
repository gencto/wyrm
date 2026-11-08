import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

import '../buttons/segmented_tabs.dart';
import '../charts/trend_chart.dart';
import '../containers/action_card.dart';
import '../containers/fact_grid.dart';
import '../containers/inspector.dart';
import '../containers/section_label.dart';
import '../forms/action_form.dart';
import '../forms/param_form.dart';
import '../indicators/key_text.dart';
import '../indicators/quality_mark.dart';
import '../indicators/status_pill.dart';
import '../overlays/log_view.dart';
import '../tables/row_table.dart';
import '../theme/extensions/colors.dart';
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

/// What the inspector shows: a point, an action's form, or a node's
/// properties.
sealed class ExplorerInspectorVm extends Equatable {
  const ExplorerInspectorVm();
}

/// A point: its live value, its facts, the field that stages a new value.
final class PointInspectorVm extends ExplorerInspectorVm {
  const PointInspectorVm({
    required this.name,
    required this.display,
    required this.value,
    required this.quality,
    required this.facts,
    this.edit,
    this.editLabel = '',
    this.stageLabel = '',
    this.readOnlyReason,
  });

  final String name;
  final String? display;

  /// The value with its unit.
  final String value;
  final QualityMarkVm quality;
  final List<FactVm> facts;

  /// The field that stages a set; null when the point cannot be set.
  final ParamFieldVm? edit;
  final String editLabel;
  final String stageLabel;
  final String? readOnlyReason;

  @override
  List<Object?> get props => [
    name,
    display,
    value,
    quality,
    facts,
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

/// A node that is not a point: its properties (the property sheet).
final class NodeInspectorVm extends ExplorerInspectorVm {
  const NodeInspectorVm({
    required this.title,
    required this.facts,
    this.cfg = const [],
    this.attr = const [],
    this.cfgLabel = 'cfg',
    this.attrLabel = 'attr',
  });

  final String title;
  final List<FactVm> facts;
  final List<FactVm> cfg;
  final List<FactVm> attr;
  final String cfgLabel;
  final String attrLabel;

  @override
  List<Object?> get props => [title, facts, cfg, attr, cfgLabel, attrLabel];
}

/// Board *Studio · Explorer* with *Explorer · Actions of a node*: the
/// tree, the selected node's tabs, and its inspector.
class ExplorerPage extends StatelessWidget {
  const ExplorerPage({
    required this.treeLabel,
    required this.tree,
    required this.onTap,
    required this.onToggle,
    required this.tabs,
    required this.tab,
    required this.onTab,
    this.onMenu,
    this.treeNote,
    this.keyName,
    this.title,
    this.pill,
    this.empty = '',
    this.pointColumns = const [],
    this.points = const [],
    this.pointsNote,
    this.pointsEmpty,
    this.onPoint,
    this.params = const [],
    this.paramsNote,
    this.actionGroups = const [],
    this.onAction,
    this.result,
    this.ranges = const [],
    this.range = '',
    this.onRange,
    this.trend = const [],
    this.trendLabels = const ('', ''),
    this.trendEmpty = '',
    this.historyColumns = const [],
    this.historyRows = const [],
    this.inspector,
    this.onSubmit,
    this.onCloseInspector,
    this.busy = false,
    super.key,
  });

  final String treeLabel;
  final List<TreeRowVm> tree;
  final ValueChanged<String> onTap;
  final ValueChanged<String> onToggle;
  final void Function(String id, Offset at)? onMenu;
  final String? treeNote;

  final String? keyName;
  final String? title;
  final StatusPillVm? pill;

  /// Shown when nothing is selected.
  final String empty;
  final List<TabItemVm> tabs;
  final String tab;
  final ValueChanged<String> onTab;

  final List<ColumnVm> pointColumns;
  final List<RowVm> points;
  final String? pointsNote;
  final String? pointsEmpty;
  final ValueChanged<String>? onPoint;

  final List<FactVm> params;
  final String? paramsNote;

  final List<ActionCardGroupVm> actionGroups;
  final ValueChanged<String>? onAction;
  final ResultVm? result;

  final List<TabItemVm> ranges;
  final String range;
  final ValueChanged<String>? onRange;
  final List<TrendSeriesVm> trend;
  final (String, String) trendLabels;
  final String trendEmpty;
  final List<ColumnVm> historyColumns;
  final List<RowVm> historyRows;

  final ExplorerInspectorVm? inspector;
  final ValueChanged<Map<String, Object?>>? onSubmit;
  final VoidCallback? onCloseInspector;
  final bool busy;

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
        note: treeNote,
        width: wide ? 290 : 240,
      );
      final work = _workspace(context);
      final ins = inspector;
      return Row(
        crossAxisAlignment: .stretch,
        children: [
          if (box.maxWidth >= 700) treePanel,
          Expanded(child: work),
          if (ins != null && wide) _inspector(context, ins),
        ],
      );
    },
  );

  Widget _workspace(BuildContext context) {
    final c = context.colors;
    if (title == null) {
      return Center(
        child: Text(empty, style: TextStyle(fontSize: 14, color: c.text4)),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 40),
      children: [
        if (keyName case final k?) KeyText(k, color: c.text3),
        const SizedBox(height: 10),
        Wrap(
          spacing: 12,
          crossAxisAlignment: .center,
          children: [
            Text(title!, style: Theme.of(context).textTheme.headlineSmall),
            if (pill case final p?) StatusPill(vm: p, dense: true),
          ],
        ),
        const SizedBox(height: 16),
        SegmentedTabs(tabs: tabs, selected: tab, onSelect: onTab),
        const SizedBox(height: 18),
        ...switch (tab) {
          'params' => [
            if (paramsNote case final n?) ...[
              Text(n, style: TextStyle(fontSize: 13, color: c.text3)),
              const SizedBox(height: 12),
            ],
            FactGrid(facts: params, labelWidth: 180),
          ],
          'actions' => [
            for (final g in actionGroups) ...[
              SectionLabel(g.label),
              const SizedBox(height: 4),
              Text(g.note, style: TextStyle(fontSize: 12, color: c.text4)),
              const SizedBox(height: 10),
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
              const SizedBox(height: 20),
            ],
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
              const SizedBox(height: 10),
              if (r.rows.isNotEmpty)
                RowTable(columns: r.columns, rows: r.rows)
              else
                SizedBox(height: 260, child: LogView(lines: r.lines)),
            ],
          ],
          'history' => [
            SegmentedTabs(
              tabs: ranges,
              selected: range,
              onSelect: onRange ?? (_) {},
            ),
            const SizedBox(height: 16),
            TrendChart(
              series: trend,
              empty: trendEmpty,
              timeLabels: trendLabels,
            ),
            const SizedBox(height: 16),
            if (historyRows.isNotEmpty)
              RowTable(
                columns: historyColumns,
                rows: historyRows,
                rowHeight: 40,
              ),
          ],
          _ => [
            RowTable(
              columns: pointColumns,
              rows: points,
              onTap: onPoint,
              empty: pointsEmpty,
              rowHeight: 40,
            ),
            if (pointsNote case final n?) ...[
              const SizedBox(height: 8),
              Text(n, style: TextStyle(fontSize: 12, color: c.text4)),
            ],
          ],
        },
      ],
    );
  }

  Widget _inspector(BuildContext context, ExplorerInspectorVm ins) {
    final c = context.colors;
    return switch (ins) {
      PointInspectorVm() => Inspector(
        eyebrow: 'Point',
        title: ins.name,
        onClose: onCloseInspector,
        header: Column(
          crossAxisAlignment: .start,
          spacing: 6,
          children: [
            if (ins.display case final d?)
              Text(d, style: TextStyle(fontSize: 13, color: c.text3)),
            Row(
              spacing: 12,
              children: [
                Flexible(
                  child: Text(ins.value, style: mono(size: 22, color: c.text1)),
                ),
                QualityMark(vm: ins.quality, size: 12),
              ],
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: .stretch,
          spacing: 16,
          children: [
            FactGrid(facts: ins.facts, labelWidth: 96),
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
            ] else if (ins.readOnlyReason case final r?)
              Text(r, style: TextStyle(fontSize: 12, color: c.text4)),
          ],
        ),
      ),
      ActionInspectorVm() => Inspector(
        eyebrow: 'Action',
        title: ins.title,
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
                      borderRadius: BorderRadius.circular(4),
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
                borderRadius: BorderRadius.circular(8),
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
        eyebrow: 'Node',
        title: ins.title,
        onClose: onCloseInspector,
        child: Column(
          crossAxisAlignment: .stretch,
          spacing: 16,
          children: [
            FactGrid(facts: ins.facts, labelWidth: 96),
            if (ins.cfg.isNotEmpty) ...[
              SectionLabel(ins.cfgLabel),
              FactGrid(facts: ins.cfg),
            ],
            if (ins.attr.isNotEmpty) ...[
              SectionLabel(ins.attrLabel),
              FactGrid(facts: ins.attr),
            ],
          ],
        ),
      ),
    };
  }
}
