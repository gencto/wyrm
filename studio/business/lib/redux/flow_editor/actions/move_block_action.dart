import '../../app_state.dart';
import '../../common/action.dart';

/// Moves block [id] to ([x], [y]) on the canvas (its `layout`).
class MoveBlockAction extends Action {
  MoveBlockAction(this.id, this.x, this.y);

  final String id;
  final double x;
  final double y;

  @override
  AppState? reduce() {
    final d = flowEditor.draft;
    final b = d?.blocks[id];
    if (d == null || b == null) {
      return null;
    }
    return state.copyWith.flowEditor(
      draft: d.copyWith(
        blocks: d.blocks.add(id, b.copyWith(x: x, y: y)),
      ),
      dirty: true,
    );
  }
}
