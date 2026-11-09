import 'dart:async';

import '../../../wyrm/mappers/flow_canvas.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import 'validate_flow_action.dart';

/// Does again the edit that `UndoFlowAction` took back.
class RedoFlowAction extends Action {
  @override
  AppState? reduce() {
    final d = flowEditor.draft;
    final steps = flowEditor.redo;
    if (d == null || steps.isEmpty) {
      return null;
    }
    final draft = restored(steps.last, d);
    final selection = flowEditor.selection.removeWhere(
      (id) => !draft.blocks.containsKey(id),
    );
    unawaited(dispatchAndWait(ValidateFlowAction()));
    return state.copyWith.flowEditor(
      draft: draft,
      redo: steps.removeLast(),
      undo: undoPush(flowEditor.undo, d),
      undoTag: null,
      selection: selection,
      selectedBlock: selection.length == 1 ? selection.single : null,
      dirty: true,
    );
  }
}
