import 'dart:async';

import '../../../wyrm/mappers/flow_canvas.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import 'validate_flow_action.dart';

/// Takes the last edit of the draft back (flow-editor.md §13): the draft
/// before it returns, and the one it replaces goes to the redo list.
class UndoFlowAction extends Action {
  @override
  AppState? reduce() {
    final d = flowEditor.draft;
    final steps = flowEditor.undo;
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
      undo: steps.removeLast(),
      redo: flowEditor.redo.add(d),
      undoTag: null,
      selection: selection,
      selectedBlock: selection.length == 1 ? selection.single : null,
      dirty: true,
    );
  }
}
