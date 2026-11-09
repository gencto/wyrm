import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import '../../../wyrm/mappers/flow_canvas.dart';
import '../../app_state.dart';
import '../../common/action.dart';

/// Moves blocks on the canvas (their `layout`): [to] gives each its new
/// top-left corner. One step of the history; moves with the same [tag]
/// in a row (the arrow keys) are one step together.
class MoveBlocksAction extends Action {
  MoveBlocksAction(this.to, {this.tag});

  final Map<String, (double, double)> to;
  final String? tag;

  @override
  AppState? reduce() {
    final d = flowEditor.draft;
    if (d == null) {
      return null;
    }
    var blocks = d.blocks;
    for (final MapEntry(key: id, value: (x, y)) in to.entries) {
      final b = blocks[id];
      if (b != null && (b.x != x || b.y != y)) {
        blocks = blocks.add(id, b.copyWith(x: x, y: y));
      }
    }
    if (identical(blocks, d.blocks)) {
      return null;
    }
    return state.copyWith.flowEditor(
      draft: d.copyWith(blocks: blocks),
      dirty: true,
      undo: undoPush(flowEditor.undo, d, tag: tag, lastTag: flowEditor.undoTag),
      redo: const IListConst([]),
      undoTag: tag,
    );
  }
}
