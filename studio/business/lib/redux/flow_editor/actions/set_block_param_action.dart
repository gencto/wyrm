import 'dart:async';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import '../../../wyrm/mappers/flow_canvas.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import 'validate_flow_action.dart';

/// Sets parameter [name] of block [id] (null removes it).
class SetBlockParamAction extends Action {
  SetBlockParamAction(this.id, this.name, this.value);

  final String id;
  final String name;
  final Object? value;

  @override
  AppState? reduce() {
    final d = flowEditor.draft;
    final b = d?.blocks[id];
    if (d == null || b == null) {
      return null;
    }
    final cfg = value == null || value == ''
        ? b.cfg.remove(name)
        : b.cfg.add(name, value);
    unawaited(dispatchAndWait(ValidateFlowAction()));
    return state.copyWith.flowEditor(
      draft: d.copyWith(blocks: d.blocks.add(id, b.copyWith(cfg: cfg))),
      dirty: true,
      undo: undoPush(
        flowEditor.undo,
        d,
        tag: 'param:$id/$name',
        lastTag: flowEditor.undoTag,
      ),
      redo: const IListConst([]),
      undoTag: 'param:$id/$name',
    );
  }
}
