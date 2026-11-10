import 'dart:async';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import '../../../wyrm/mappers/flow_blocks.dart';
import '../../../wyrm/mappers/flow_canvas.dart';
import '../../../wyrm/mappers/flow_mapper.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import 'validate_flow_action.dart';

/// Back from the inside of a custom block (flow-editor.md §20): [levels]
/// frames up (all of them: back to the flow). What was done inside becomes
/// the block's definition, for every instance of it; in the history of the
/// level above it is one step, and only when something changed.
class LeaveBlockAction extends Action {
  LeaveBlockAction({this.levels = 1});

  final int levels;

  @override
  AppState? reduce() {
    var frames = flowEditor.frames;
    var d = flowEditor.draft;
    if (d == null || frames.isEmpty || levels < 1) {
      return null;
    }
    var undo = flowEditor.undo;
    var redo = flowEditor.redo;
    var selection = flowEditor.selection;
    for (var i = 0; i < levels && frames.isNotEmpty; i++) {
      final f = frames.last;
      final folded = foldInside(f.draft, f.block, d!);
      final changed = defOf(folded, 0) != defOf(f.draft, 0);
      undo = changed ? undoPush(f.undo, f.draft) : f.undo;
      redo = changed ? const IListConst([]) : f.redo;
      selection = f.selection.removeWhere(
        (id) => !folded.blocks.containsKey(id),
      );
      d = folded;
      frames = frames.removeLast();
    }
    unawaited(dispatchAndWait(ValidateFlowAction()));
    return state.copyWith.flowEditor(
      frames: frames,
      draft: d,
      undo: undo,
      redo: redo,
      undoTag: null,
      selection: selection,
      selectedBlock: selection.length == 1 ? selection.single : null,
      viewedField: null,
      scopePrompt: null,
    );
  }
}
