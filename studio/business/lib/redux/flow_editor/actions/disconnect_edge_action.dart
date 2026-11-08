import 'dart:async';

import '../../app_state.dart';
import '../../common/action.dart';
import 'validate_flow_action.dart';

/// Removes the wire into `<to>.<toPort>`. Unbinding a parameter keeps the
/// last value it had as its typed value: [keep] into `cfg.<param>`.
class DisconnectEdgeAction extends Action {
  DisconnectEdgeAction(this.to, this.toPort, {this.param, this.keep});

  final String to;
  final String toPort;
  final String? param;
  final Object? keep;

  @override
  AppState? reduce() {
    final d = flowEditor.draft;
    if (d == null) {
      return null;
    }
    unawaited(dispatchAndWait(ValidateFlowAction()));
    final b = d.blocks[to];
    final param = this.param;
    final blocks = b != null && param != null && keep != null
        ? d.blocks.add(to, b.copyWith(cfg: b.cfg.add(param, keep)))
        : d.blocks;
    return state.copyWith.flowEditor(
      draft: d.copyWith(
        blocks: blocks,
        edges: d.edges.removeWhere((e) => e.to == to && e.toPort == toPort),
      ),
      dirty: true,
    );
  }
}
