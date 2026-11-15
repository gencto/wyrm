import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import '../../../wyrm/mappers/flow_canvas.dart';
import '../../../wyrm/mappers/flow_layout.dart';
import '../../app_state.dart';
import '../../common/action.dart';

/// `Tidy up` (flow-editor.md §25): every block of the draft on the canvas
/// laid out again by the data flow, saved positions too. One step of the
/// history; nothing changes (and nothing is pushed) when every block is
/// already where the layout puts it.
class TidyFlowAction extends Action {
  @override
  AppState? reduce() {
    final ed = flowEditor;
    final d = ed.draft;
    if (d == null || d.blocks.isEmpty) {
      return null;
    }
    final next = tidyFlow(d, {for (final t in ed.types) t.type: t});
    final moved = d.blocks.values.any((b) {
      final n = next.blocks[b.id]!;
      return n.x != b.x || n.y != b.y;
    });
    if (!moved) {
      return null;
    }
    return state.copyWith.flowEditor(
      draft: next,
      dirty: true,
      undo: undoPush(ed.undo, d),
      redo: const IListConst([]),
      undoTag: null,
    );
  }
}
