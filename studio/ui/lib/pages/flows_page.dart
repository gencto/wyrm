import 'package:equatable/equatable.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';

import '../buttons/action_row.dart';
import '../buttons/button.dart';
import '../containers/detail_inspector.dart';
import '../containers/fact_grid.dart';
import '../containers/page_header.dart';
import '../indicators/flow_state_tag.dart';
import '../models/disabled.dart';
import '../models/tone.dart';
import '../tables/row_table.dart';
import '../theme/spacing.dart';

/// One flow of `dataflows/<id>`, as Flows draws it.
final class FlowRowVm extends Equatable {
  const FlowRowVm({
    required this.id,
    required this.state,
    this.version,
    this.problem,
    this.description,
    this.blocks = 0,
    this.reads = const [],
    this.writes = const [],
    this.deployedBy,
  });

  final String id;
  final FlowStateTag state;
  final int? version;

  /// The engine's words for what fails, with [FlowStateTag.error].
  final String? problem;
  final String? description;
  final int blocks;

  /// The keys it reads and writes, full.
  final List<String> reads;
  final List<String> writes;
  final String? deployedBy;

  @override
  List<Object?> get props => [
    id,
    state,
    version,
    problem,
    description,
    blocks,
    reads,
    writes,
    deployedBy,
  ];
}

/// What Flows draws: the site's flows, the one picked (its key and why
/// Edit is disabled, if it is) and why `New dataflow` is.
final class FlowsVm extends Equatable {
  const FlowsVm({
    required this.site,
    required this.flows,
    this.picked,
    this.pickedKey = '',
    this.newDisabled,
    this.editDisabled,
  });

  final String site;
  final List<FlowRowVm> flows;

  /// The id of the flow picked.
  final String? picked;

  /// The full key of the flow picked.
  final String pickedKey;
  final Disabled? newDisabled;
  final Disabled? editDisabled;

  @override
  List<Object?> get props => [
    site,
    flows,
    picked,
    pickedKey,
    newDisabled,
    editDisabled,
  ];
}

/// Board *Studio · Flows*: the site's flows with their state, what they
/// read and write, and the inspector of the selected one with Edit.
class FlowsPage extends StatelessWidget {
  const FlowsPage({
    required this.vm,
    required this.onNew,
    required this.onRow,
    required this.onEdit,
    super.key,
  });

  final FlowsVm vm;

  /// Opens the editor on a new flow.
  final VoidCallback onNew;

  /// A flow picked, by its id.
  final ValueChanged<String> onRow;

  /// Opens the editor on the flow of this id.
  final ValueChanged<String> onEdit;

  /// `plc1/t1, plc1/t2 → plc1/sp`: two keys of each side below their site
  /// (or below `dataflows`).
  static String _arrow(FlowRowVm f) {
    String short(List<String> keys) => keys.isEmpty
        ? '—'
        : keys
              .map(
                (k) => k.split('/').skip(k.startsWith('wy/') ? 3 : 1).join('/'),
              )
              .take(2)
              .join(', ');
    return '${short(f.reads)} → ${short(f.writes)}';
  }

  List<RowVm<String>> get _rows => [
    for (final f in vm.flows)
      RowVm(
        id: f.id,
        selected: f.id == vm.picked,
        cells: [
          CellVm(
            title: f.id,
            subtitle: f.description ?? S.current.blocksCount(f.blocks),
            strong: true,
          ),
          CellVm(
            title: f.state.label(f.version),
            tone: f.state.tone,
            subtitle: f.problem,
          ),
          CellVm(title: _arrow(f), monospace: true),
          CellVm(title: f.deployedBy ?? '—'),
        ],
      ),
  ];

  DetailInspectorVm<String>? get _inspector {
    final f = vm.flows.where((f) => f.id == vm.picked).firstOrNull;
    if (f == null) {
      return null;
    }
    return DetailInspectorVm(
      eyebrow: S.current.dataflow,
      title: f.id,
      pill: f.state.pill(f.version),
      keyName: vm.pickedKey,
      facts: [
        if (f.description case final d?)
          FactVm(label: S.current.factAbout, value: d),
        FactVm(
          label: S.current.factRunning,
          value: f.version == null ? '—' : 'v${f.version}',
        ),
        FactVm(label: S.current.colReadsWrites, value: _arrow(f), mono: true),
        FactVm(label: S.current.factBlocks, value: '${f.blocks}'),
        if (f.problem case final p?)
          FactVm(label: S.current.factProblem, value: p),
      ],
      groups: [
        ActionGroupVm(
          label: S.current.groupWork,
          actions: [
            ActionRowVm(
              id: f.id,
              icon: 'action_edit',
              title: S.current.editDataflow,
              description: S.current.editDataflowNote,
              tone: Tone.ember,
              disabledReason: vm.editDisabled?.text,
            ),
          ],
        ),
      ],
      footer: S.current.flowsFooter,
    );
  }

  @override
  Widget build(BuildContext context) {
    final newReason = vm.newDisabled?.text;
    final body = ListView(
      padding: Insets.workspace,
      children: [
        PageHeader(
          title: S.current.flowsOn(vm.site),
          subtitle: S.current.flowsSubtitle,
          trailing: Button.primary(
            label: S.current.newDataflow,
            icon: 'ui_add',
            disabledReason: newReason,
            onPressed: newReason == null ? onNew : null,
          ),
        ),
        Gaps.underHeader,
        RowTable(
          columns: [
            ColumnVm(S.current.colFlow, flex: 3),
            ColumnVm(S.current.colState, flex: 3),
            ColumnVm(S.current.colReadsWrites, flex: 4),
            ColumnVm(S.current.colDeployedBy, flex: 2),
          ],
          rows: _rows,
          onTap: onRow,
          empty: S.current.noFlows,
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, box) {
        final ins = _inspector;
        if (ins == null || box.maxWidth < 1000) {
          return body;
        }
        return Row(
          crossAxisAlignment: .stretch,
          children: [
            Expanded(child: body),
            DetailInspector(vm: ins, onAction: onEdit),
          ],
        );
      },
    );
  }
}
