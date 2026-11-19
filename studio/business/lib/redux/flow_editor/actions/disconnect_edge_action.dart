import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/json_value.dart';

import '../../../wyrm/mappers/flow_canvas.dart';

import '../../app_state.dart';
import '../../common/action.dart';

/// Removes the wire into `<to>.<toPort>`. Unbinding a parameter keeps the
/// last value it had as its typed value: [keep] into `cfg.<param>`, when
/// it is JSON within [JsonValue.maxDepth].
class DisconnectEdgeAction extends Action {
  DisconnectEdgeAction(this.to, this.toPort, {this.param, this.keep});

  final String to;
  final String toPort;
  final String? param;
  final Object? keep;

  @override
  AppState? reduce() {
    final d = flowEditor.draft;
    if (d == null) {
      return null;
    }
    final b = d.blocks[to];
    final param = this.param;
    // A live value comes from the wire: it is kept only when it is JSON
    // within the bound, since the inspector reads the config as JSON while
    // it builds. One that is not (bytes, nested past the bound) is not
    // kept: the parameter shows its default again.
    final keep = this.keep;
    final blocks =
        b != null && param != null && keep != null && JsonValue.isJson(keep)
        ? d.blocks.add(to, b.copyWith(cfg: b.cfg.add(param, keep)))
        : d.blocks;
    return state.copyWith.flowEditor(
      draft: d.copyWith(
        blocks: blocks,
        edges: d.edges.removeWhere((e) => e.to == to && e.toPort == toPort),
      ),
      dirty: true,
      undo: undoPush(flowEditor.undo, d),
      redo: const IListConst([]),
      undoTag: null,
    );
  }
}
