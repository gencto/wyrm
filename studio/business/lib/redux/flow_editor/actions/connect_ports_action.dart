import 'dart:async';

import 'package:models/flow_edge.dart';

import '../../app_state.dart';
import '../../common/action.dart';
import 'validate_flow_action.dart';

/// Wires `<from>.<fromPort>` to `<to>.<toPort>`; an input takes one wire,
/// so a wire already into it is replaced.
class ConnectPortsAction extends Action {
  ConnectPortsAction(this.from, this.fromPort, this.to, this.toPort);

  final String from;
  final String fromPort;
  final String to;
  final String toPort;

  @override
  AppState? reduce() {
    final d = flowEditor.draft;
    if (d == null || from == to) {
      return null;
    }
    unawaited(dispatchAndWait(ValidateFlowAction()));
    return state.copyWith.flowEditor(
      draft: d.copyWith(
        edges: d.edges
            .removeWhere((e) => e.to == to && e.toPort == toPort)
            .add(
              FlowEdge(from: from, fromPort: fromPort, to: to, toPort: toPort),
            ),
      ),
      dirty: true,
    );
  }
}
