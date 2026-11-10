import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import '../../../wyrm/mappers/flow_canvas.dart';
import '../../../wyrm/mappers/flow_fields.dart';
import '../../app_state.dart';
import '../../common/action.dart';

/// Pins field [field] (its id, `p:input_min`) of block [block] to the
/// block, or takes it off ([pinned] false): the row leaves the canvas and
/// stays in the inspector. A bound field cannot be taken off. Kept in the
/// definition's `layout` (flow-editor.md §12).
class SetFieldPinAction extends Action {
  SetFieldPinAction(this.block, this.field, {required this.pinned});

  final String block;
  final String field;
  final bool pinned;

  @override
  AppState? reduce() {
    final d = flowEditor.draft;
    final b = d?.blocks[block];
    if (d == null || b == null) {
      return null;
    }
    final t = flowEditor.allTypes.where((t) => t.type == b.type).firstOrNull;
    final f = fieldsOf(
      t,
      b,
      edges: d.edges,
    ).where((f) => f.id == field).firstOrNull;
    final next = f == null ? null : withPin(b, f, d.edges, pinned: pinned);
    if (next == null) {
      return null;
    }
    return state.copyWith.flowEditor(
      draft: d.copyWith(blocks: d.blocks.add(block, next)),
      dirty: true,
      undo: undoPush(flowEditor.undo, d),
      redo: const IListConst([]),
      undoTag: null,
    );
  }
}
