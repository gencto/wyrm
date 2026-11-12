import 'package:async_redux/async_redux.dart';
import 'package:auto_route/auto_route.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/flows/actions/follow_flows_action.dart';
import 'package:business/redux/flows/actions/set_selected_flow_action.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:models/flow_summary.dart';
import 'package:ui/buttons/action_row.dart';
import 'package:ui/containers/detail_inspector.dart';
import 'package:ui/containers/fact_grid.dart';
import 'package:ui/indicators/status_pill.dart';
import 'package:ui/models/tone.dart';
import 'package:ui/pages/flows_page.dart';
import 'package:ui/tables/row_table.dart';

import '../common/flow_state.dart';
import '../common/tab_visibility.dart';
import '../navigation/app_router.dart';
import '../navigation/go_action.dart';

/// The id the editor route takes for a flow not made yet.
const newFlowId = '+new';

@RoutePage()
class FlowsPageConnector extends StatelessWidget {
  const FlowsPageConnector({super.key});

  @override
  Widget build(BuildContext context) => StoreConnector<AppState, _Vm>(
    debug: this,
    vm: () => _Factory(this),
    builder: (context, vm) => TabVisibility(
      onShow: vm.onShow,
      onHide: vm.onHide,
      child: FlowsPage(
        title: S.current.flowsOn(vm.site),
        subtitle: S.current.flowsSubtitle,
        newLabel: S.current.newDataflow,
        newReason: vm.newReason,
        onTapFlowEditor: () => vm.onTapFlowEditor(newFlowId),
        columns: [
          ColumnVm(S.current.colFlow, flex: 3),
          ColumnVm(S.current.colState, flex: 3),
          ColumnVm(S.current.colReadsWrites, flex: 4),
          ColumnVm(S.current.colDeployedBy, flex: 2),
        ],
        rows: vm.rows,
        empty: S.current.noFlows,
        onRow: vm.onRow,
        inspector: vm.inspector,
        onAction: (a) => vm.onTapFlowEditor(a),
      ),
    ),
  );
}

/// Factory that creates a view-model for the StoreConnector.
class _Factory extends VmFactory<AppState, FlowsPageConnector, _Vm>
    with Selectors {
  _Factory(super._connector);

  static String _arrow(FlowSummary f) {
    String short(List<String> keys) => keys.isEmpty
        ? '—'
        : keys
              .map(
                (k) => k.split('/').skip(k.startsWith('wy/') ? 3 : 1).join('/'),
              )
              .take(2)
              .join(', ');
    return '${short(f.reads.unlock)} → ${short(f.writes.unlock)}';
  }

  (Tone, String, String?) _state(FlowSummary f) => flowStateOf(f);

  @override
  _Vm fromStore() {
    final root = site.root ?? '';
    // The rows with their live state while Flows follows `dataflows/*`.
    final table = flows.shownTable;
    final list = [for (final id in flows.view) ?table[id]];
    final sel = flows.selectedFlow;
    final f = sel == null ? null : table[sel];
    final configReason = site.needs('config', '$root/dataflows');
    return _Vm(
      site: site.viewed ?? '',
      newReason: configReason,
      rows: [
        for (final f in list)
          () {
            final (tone, word, problem) = _state(f);
            return RowVm(
              id: f.id,
              selected: f.id == sel,
              cells: [
                CellVm(
                  title: f.id,
                  subtitle: f.description ?? S.current.blocksCount(f.blocks),
                  strong: true,
                ),
                CellVm(title: word, tone: tone, subtitle: problem),
                CellVm(title: _arrow(f), monospace: true),
                CellVm(title: f.deployedBy ?? '—'),
              ],
            );
          }(),
      ],
      inspector: f == null
          ? null
          : () {
              final (tone, word, problem) = _state(f);
              return DetailInspectorVm(
                eyebrow: S.current.dataflow,
                title: f.id,
                pill: StatusPillVm(label: word, tone: tone),
                keyName: '$root/dataflows/${f.id}',
                facts: [
                  if (f.description case final d?)
                    FactVm(label: S.current.factAbout, value: d),
                  FactVm(
                    label: S.current.factRunning,
                    value: f.version == null ? '—' : 'v${f.version}',
                  ),
                  FactVm(
                    label: S.current.colReadsWrites,
                    value: _arrow(f),
                    mono: true,
                  ),
                  FactVm(label: S.current.factBlocks, value: '${f.blocks}'),
                  if (problem != null)
                    FactVm(label: S.current.factProblem, value: problem),
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
                        disabledReason: site.needs(
                          'read',
                          '$root/dataflows/${f.id}',
                        ),
                      ),
                    ],
                  ),
                ],
                footer: S.current.flowsFooter,
              );
            }(),
      // The live list of `dataflows` fills and keeps the table; a
      // definition is read only for a new flow or a new version.
      onShow: () => dispatchSync(FollowFlowsAction(show: true)),
      onHide: () => dispatchSync(FollowFlowsAction(show: false)),
      onRow: (id) => dispatchSync(SetSelectedFlowAction(id)),
      onTapFlowEditor: (id) => dispatch(GoAction.push(FlowEditorRoute(id: id))),
    );
  }
}

/// The view-model holds the part of the Store state the dumb-widget needs.
class _Vm extends Vm {
  _Vm({
    required this.site,
    required this.newReason,
    required this.rows,
    required this.inspector,
    required this.onShow,
    required this.onHide,
    required this.onRow,
    required this.onTapFlowEditor,
  }) : super(equals: [site, newReason, rows, inspector]);

  final String site;
  final String? newReason;
  final List<RowVm> rows;
  final DetailInspectorVm? inspector;
  final VoidCallback onShow;
  final VoidCallback onHide;
  final ValueChanged<String> onRow;
  final void Function(String) onTapFlowEditor;
}
