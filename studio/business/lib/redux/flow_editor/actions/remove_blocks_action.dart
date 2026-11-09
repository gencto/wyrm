import 'dart:async';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import '../../../wyrm/mappers/flow_blocks.dart';
import '../../../wyrm/mappers/flow_canvas.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import 'validate_flow_action.dart';

/// Removes the blocks [ids] and every edge to or from them.
class RemoveBlocksAction extends Action {
  RemoveBlocksAction(this.ids);

  final Iterable<String> ids;

  @override
  AppState? reduce() {
    final d = flowEditor.draft;
    final gone = {
      for (final id in ids)
        // The inputs and outputs blocks of a block's inside stay.
        if (!isBoundary(id) && (d?.blocks.containsKey(id) ?? false)) id,
    };
    if (d == null || gone.isEmpty) {
      return null;
    }
    unawaited(dispatchAndWait(ValidateFlowAction()));
    final selection = flowEditor.selection.removeAll(gone);
    return state.copyWith.flowEditor(
      draft: withoutBlocks(d, gone),
      selection: selection,
      selectedBlock: selection.length == 1 ? selection.single : null,
      dirty: true,
      undo: undoPush(flowEditor.undo, d),
      redo: const IListConst([]),
      undoTag: null,
    );
  }
}
