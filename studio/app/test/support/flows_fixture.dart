import 'package:business/redux/app_state.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/flow_summary.dart';

import 'screen_app.dart';

/// The flows of `plant`: one running, one failing, one stopped, one never
/// deployed.
final flowsOfPlant = [
  const FlowSummary(
    id: 'heat',
    version: 2,
    running: true,
    deployedBy: 'olena',
    description: 'Boiler heat',
    blocks: 4,
    reads: IListConst([
      '$plant/downstream/plc1/t1',
      '$plant/downstream/plc1/t2',
      '$plant/storage/limits/max',
    ]),
    writes: IListConst(['$plant/downstream/plc1/sp']),
  ),
  const FlowSummary(
    id: 'alarm',
    version: 3,
    problem: 'rhai: unknown variable `t3`',
    blocks: 7,
    reads: IListConst(['dataflows/heat/out']),
  ),
  const FlowSummary(id: 'old', version: 1, blocks: 2),
  const FlowSummary(id: 'draft'),
];

/// [s] with the flows of `plant`, [selected] picked.
AppState withFlows(AppState s, {String? selected}) => s.copyWith(
  flows: s.flows.copyWith(
    table: IMap.fromValues(keyMapper: (f) => f.id, values: flowsOfPlant),
    view: [for (final f in flowsOfPlant) f.id].lock,
    selectedFlow: selected,
  ),
);
