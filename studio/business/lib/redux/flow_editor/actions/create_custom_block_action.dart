import 'dart:async';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import '../../../wyrm/mappers/flow_blocks.dart';
import '../../../wyrm/mappers/flow_canvas.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import 'validate_flow_action.dart';

/// `Create custom block…` (flow-editor.md §20): the blocks [ids] become the
/// inside of a new block [spec] of this flow and are replaced by one
/// instance of it, selected. One step of the history.
class CreateCustomBlockAction extends Action {
  CreateCustomBlockAction(this.ids, this.spec);

  final Set<String> ids;
  final CustomBlockSpec spec;

  @override
  AppState? reduce() {
    final d = flowEditor.draft;
    final made = d == null
        ? null
        : createCustomBlock(d, {
            for (final id in ids)
              if (!isBoundary(id)) id,
          }, spec);
    if (d == null || made == null) {
      return null;
    }
    final (next, id) = made;
    unawaited(dispatchAndWait(ValidateFlowAction()));
    return state.copyWith.flowEditor(
      draft: next,
      selection: {id}.toISet(),
      selectedBlock: id,
      dirty: true,
      undo: undoPush(flowEditor.undo, d),
      redo: const IListConst([]),
      undoTag: null,
    );
  }
}
