import 'package:models/flow_summary.dart';
import 'package:ui/indicators/flow_state_tag.dart';
import 'package:ui/pages/flows_page.dart';

/// A flow's state as `ui` draws it: a state Studio could not read first
/// (it is none of the others), then an error, then running, then a
/// version that does not run, then none.
extension FlowStateTagOf on FlowSummary {
  FlowStateTag get tag => switch (this) {
    FlowSummary(unreadable: true) => .unreadable,
    FlowSummary(problem: _?) => .error,
    FlowSummary(running: true) => .deployed,
    FlowSummary(version: _?) => .stopped,
    _ => .notDeployed,
  };

  /// The flow as a row of Flows.
  FlowRowVm get row => FlowRowVm(
    id: id,
    state: tag,
    version: version,
    problem: problem,
    description: description,
    blocks: blocks,
    reads: reads.unlock,
    writes: writes.unlock,
    deployedBy: deployedBy,
  );
}
