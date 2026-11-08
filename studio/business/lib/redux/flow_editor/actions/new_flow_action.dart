import 'dart:async';

import '../../app_state.dart';
import '../../common/action.dart';
import 'validate_flow_action.dart';

/// Names the flow being made ([id] is its key segment, `[A-Za-z0-9_]+`).
class NewFlowAction extends Action {
  NewFlowAction(this.id);

  final String id;

  @override
  AppState? reduce() {
    final d = flowEditor.draft;
    if (d == null) {
      return null;
    }
    unawaited(dispatchAndWait(ValidateFlowAction()));
    return state.copyWith.flowEditor(
      flowId: id,
      draft: d.copyWith(id: id),
      dirty: true,
    );
  }
}
