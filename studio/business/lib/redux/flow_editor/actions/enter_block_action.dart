import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/flow_frame.dart';

import '../../../wyrm/mappers/flow_blocks.dart';
import '../../app_state.dart';
import '../../common/action.dart';

/// `Edit custom block` / `Open inside` (flow-editor.md §20): the canvas
/// shows the inside of block [block] of the draft, opened from [instance]
/// (its inner nodes then show live values) or from the palette. What the
/// canvas showed waits in `flowEditor.frames` with its history.
class EnterBlockAction extends Action {
  EnterBlockAction(this.block, {this.instance});

  final String block;
  final String? instance;

  @override
  AppState? reduce() {
    final d = flowEditor.draft;
    final inner = d == null ? null : insideDraftOf(d, block);
    // A block does not open inside itself (the engine refuses a block that
    // contains itself), and at most four deep (spec 06 0.2.24).
    if (d == null ||
        inner == null ||
        flowEditor.frames.any((f) => f.block == block) ||
        flowEditor.frames.length >= 4) {
      return null;
    }
    return state.copyWith.flowEditor(
      frames: flowEditor.frames.add(
        FlowFrame(
          draft: d,
          block: block,
          instance: instance,
          undo: flowEditor.undo,
          redo: flowEditor.redo,
          selection: flowEditor.selection,
        ),
      ),
      draft: inner,
      undo: const IListConst([]),
      redo: const IListConst([]),
      undoTag: null,
      selection: const ISetConst({}),
      selectedBlock: null,
      viewedField: null,
      scopePrompt: null,
    );
  }
}
