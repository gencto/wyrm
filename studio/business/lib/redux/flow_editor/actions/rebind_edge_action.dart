import 'dart:async';

import 'package:models/flow_edge.dart';

import '../../app_state.dart';
import '../../common/action.dart';
import 'validate_flow_action.dart';

/// Moves the wire into `<oldTo>.<oldToPort>` so that it feeds
/// `<to>.<toPort>` instead (a wire picked up from its input and dropped on
/// another, spec §4). Its source stays; a wire already into the new input
/// is replaced, as by `ConnectPortsAction`. The input it leaves keeps the
/// last value it had when it is a parameter: [keep] into `cfg.<param>`, as
/// `DisconnectEdgeAction` does.
class RebindEdgeAction extends Action {
  RebindEdgeAction(
    this.oldTo,
    this.oldToPort,
    this.to,
    this.toPort, {
    this.param,
    this.keep,
  });

  final String oldTo;
  final String oldToPort;
  final String to;
  final String toPort;
  final String? param;
  final Object? keep;

  @override
  AppState? reduce() {
    final d = flowEditor.draft;
    if (d == null || (oldTo == to && oldToPort == toPort)) {
      return null;
    }
    final wire = d.edges
        .where((e) => e.to == oldTo && e.toPort == oldToPort)
        .firstOrNull;
    if (wire == null || wire.from == to) {
      return null;
    }
    unawaited(dispatchAndWait(ValidateFlowAction()));
    final b = d.blocks[oldTo];
    final param = this.param;
    final blocks = b != null && param != null && keep != null
        ? d.blocks.add(oldTo, b.copyWith(cfg: b.cfg.add(param, keep)))
        : d.blocks;
    return state.copyWith.flowEditor(
      draft: d.copyWith(
        blocks: blocks,
        edges: d.edges
            .removeWhere(
              (e) =>
                  (e.to == oldTo && e.toPort == oldToPort) ||
                  (e.to == to && e.toPort == toPort),
            )
            .add(
              FlowEdge(
                from: wire.from,
                fromPort: wire.fromPort,
                to: to,
                toPort: toPort,
              ),
            ),
      ),
      dirty: true,
    );
  }
}
