import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/block_type.dart';
import 'package:models/field_id.dart';
import 'package:models/port_end.dart';

import '../../../wyrm/mappers/flow_blocks.dart';
import '../../../wyrm/mappers/flow_canvas.dart';
import '../../app_state.dart';
import '../../common/action.dart';

/// Adds a block of [type] at ([x], [y]) with the defaults of its choice
/// parameters (and [cfg] over them: a point dragged from the tree gives its
/// key) under a fresh id (`<type><n>`), and selects it ([withNewBlock]).
class AddBlockAction extends Action {
  AddBlockAction(
    this.type,
    this.x,
    this.y, {
    this.cfg = const {},
    this.pins = const {},
    this.into,
  });

  final BlockType type;
  final double x;
  final double y;
  final Map<String, Object?> cfg;

  /// Fields taken off the block (or pinned to it) from the start: an
  /// action's optional arguments stay in the inspector.
  final Map<FieldId, bool> pins;

  /// Also wire the new block's `out` into this input: a point of the Tree
  /// tab dropped on a field.
  final PortEnd? into;

  @override
  AppState? reduce() {
    final d = flowEditor.draft;
    if (d == null) {
      return null;
    }
    final types = flowEditor.allTypes;
    final into = this.into;
    final added = withNewBlock(
      types,
      d,
      type,
      x,
      y,
      cfg: cfg,
      pins: pins,
      into: into,
    );
    return state.copyWith.flowEditor(
      // A point dropped on a key field: its wire needs a scope too.
      scopePrompt: into != null && scopeAsked(types, d, into.block, into.port)
          ? into.block
          : flowEditor.scopePrompt,
      draft: added.draft,
      selectedBlock: into == null ? added.id : flowEditor.selectedBlock,
      selection: into == null ? {added.id}.toISet() : flowEditor.selection,
      dirty: true,
      undo: undoPush(flowEditor.undo, d),
      redo: const IListConst([]),
      undoTag: null,
    );
  }
}
