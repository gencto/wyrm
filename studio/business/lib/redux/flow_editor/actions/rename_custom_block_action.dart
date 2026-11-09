import 'dart:async';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import '../../../wyrm/mappers/flow_blocks.dart';
import '../../../wyrm/mappers/flow_canvas.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import 'validate_flow_action.dart';

/// Renames custom block [from] of this flow to [to]: its definition and
/// every instance of it. Only while the canvas shows the flow itself.
class RenameCustomBlockAction extends Action {
  RenameCustomBlockAction(this.from, this.to);

  final String from;
  final String to;

  @override
  AppState? reduce() {
    final d = flowEditor.draft;
    final next = d == null || flowEditor.frames.isNotEmpty
        ? null
        : renameBlock(d, from, to.trim());
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
