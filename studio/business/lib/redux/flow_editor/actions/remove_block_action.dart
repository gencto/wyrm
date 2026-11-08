import 'dart:async';

import '../../app_state.dart';
import '../../common/action.dart';
import 'validate_flow_action.dart';

/// Removes block [id] and every edge to or from it.
class RemoveBlockAction extends Action {
  RemoveBlockAction(this.id);

  final String id;

  @override
  AppState? reduce() {
    final d = flowEditor.draft;
    if (d == null) {
      return null;
    }
    unawaited(dispatchAndWait(ValidateFlowAction()));
    return state.copyWith.flowEditor(
      draft: d.copyWith(
        blocks: d.blocks.remove(id),
        edges: d.edges.removeWhere((e) => e.from == id || e.to == id),
      ),
      selectedBlock: flowEditor.selectedBlock == id
          ? null
          : flowEditor.selectedBlock,
      dirty: true,
    );
  }
}
