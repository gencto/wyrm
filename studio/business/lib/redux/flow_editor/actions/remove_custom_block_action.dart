import 'dart:async';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import '../../../wyrm/mappers/flow_blocks.dart';
import '../../../wyrm/mappers/flow_canvas.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import 'validate_flow_action.dart';

/// Deletes custom block [name] from this flow's definition. Only a block
/// no instance uses, and only while the canvas shows the flow itself.
class RemoveCustomBlockAction extends Action {
  RemoveCustomBlockAction(this.name);

  final String name;

  @override
  AppState? reduce() {
    final d = flowEditor.draft;
    final next = d == null || flowEditor.frames.isNotEmpty
        ? null
        : removeBlock(d, name);
    if (d == null || next == null) {
      return null;
    }
    unawaited(dispatchAndWait(ValidateFlowAction()));
    return state.copyWith.flowEditor(
      draft: next,
      dirty: true,
      undo: undoPush(flowEditor.undo, d),
      redo: const IListConst([]),
      undoTag: null,
    );
  }
}
