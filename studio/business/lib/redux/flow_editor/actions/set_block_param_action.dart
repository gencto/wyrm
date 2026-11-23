import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import 'package:models/json_value.dart';
import 'package:models/undo_kind.dart';
import 'package:models/undo_tag.dart';

import '../../../wyrm/mappers/flow_canvas.dart';
import '../../app_state.dart';
import '../../common/action.dart';

/// Sets parameter [name] of block [id] (`null` or an empty text removes
/// it).
class SetBlockParamAction extends Action {
  SetBlockParamAction(this.id, this.name, this.value);

  final String id;
  final String name;
  final JsonValue value;

  @override
  AppState? reduce() {
    final d = flowEditor.draft;
    final b = d?.blocks[id];
    if (d == null || b == null) {
      return null;
    }
    final tag = UndoTag(UndoKind.param, block: id, name: name);
    final cfg = switch (value) {
      JsonNull() || JsonText(text: '') => b.cfg.remove(name),
      _ => b.cfg.add(name, value.raw),
    };
    return state.copyWith.flowEditor(
      draft: d.copyWith(blocks: d.blocks.add(id, b.copyWith(cfg: cfg))),
      dirty: true,
      undo: undoPush(
        flowEditor.undo,
        d,
        tag: tag,
        lastTag: flowEditor.undoTag,
      ),
      redo: const IListConst([]),
      undoTag: tag,
    );
  }
}
