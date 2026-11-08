import 'dart:async';

import '../../app_state.dart';
import '../../common/action.dart';
import 'validate_flow_action.dart';

/// Removes the wire into `<to>.<toPort>`.
class DisconnectEdgeAction extends Action {
  DisconnectEdgeAction(this.to, this.toPort);

  final String to;
  final String toPort;

  @override
  AppState? reduce() {
    final d = flowEditor.draft;
    if (d == null) {
      return null;
    }
    unawaited(dispatchAndWait(ValidateFlowAction()));
    return state.copyWith.flowEditor(
      draft: d.copyWith(
        edges: d.edges.removeWhere((e) => e.to == to && e.toPort == toPort),
      ),
      dirty: true,
    );
  }
}
