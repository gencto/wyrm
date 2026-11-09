import 'dart:async';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import '../../../wyrm/mappers/flow_canvas.dart';
import '../../../wyrm/mappers/flow_mapper.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import 'validate_flow_action.dart';

/// Types [value] into operand [port] of block [id]: the node's config
/// `values.<port>` (ADR 0038 §7; null or empty text removes it). A binding
/// into the port wins over it and leaves it in the config, so it returns
/// on unbind. A port that takes no constant (a parameter's port, a type
/// without catalog `values: true`) changes nothing.
class SetOperandValueAction extends Action {
  SetOperandValueAction(this.id, this.port, this.value);

  final String id;
  final String port;
  final Object? value;

  @override
  AppState? reduce() {
    final d = flowEditor.draft;
    final b = d?.blocks[id];
    if (d == null || b == null) {
      return null;
    }
    final t = flowEditor.allTypes.where((t) => t.type == b.type).firstOrNull;
    final cfg = cfgWithOperandValue(t, b, port, value);
    if (cfg == null || sameCfg(cfg, b.cfg)) {
      return null;
    }
    unawaited(dispatchAndWait(ValidateFlowAction()));
    return state.copyWith.flowEditor(
      draft: d.copyWith(blocks: d.blocks.add(id, b.copyWith(cfg: cfg))),
      dirty: true,
      undo: undoPush(
        flowEditor.undo,
        d,
        tag: 'operand:$id/$port',
        lastTag: flowEditor.undoTag,
      ),
      redo: const IListConst([]),
      undoTag: 'operand:$id/$port',
    );
  }
}
