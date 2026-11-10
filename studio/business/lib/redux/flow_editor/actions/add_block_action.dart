import 'dart:async';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/flow_block.dart';
import 'package:models/flow_edge.dart';
import 'package:models/param_spec.dart';

import '../../../wyrm/mappers/flow_blocks.dart';
import '../../../wyrm/mappers/flow_canvas.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import 'validate_flow_action.dart';

/// Adds a block of [type] at ([x], [y]) with the defaults of its choice
/// parameters (and [cfg] over them: a point dragged from the tree gives its
/// key) under a fresh id (`<type><n>`), and selects it.
///
/// Other defaults stay out of the definition: the block shows them as the
/// values of its fields, and the engine applies them itself. Writing them
/// would change what a block means (a `scale` with a range parameter maps
/// from the range: it is in its range form).
class AddBlockAction extends Action {
  AddBlockAction(
    this.type,
    this.x,
    this.y, {
    this.cfg = const {},
    this.pins = const {},
    this.into,
    this.tag,
  });

  /// With the tag of the step before it, both are one step of the history
  /// (a library block copied into the flow, then its instance).
  final String? tag;

  final String type;
  final double x;
  final double y;
  final Map<String, Object?> cfg;

  /// Fields taken off the block (or pinned to it) from the start, by field
  /// id: an action's optional arguments stay in the inspector.
  final Map<String, bool> pins;

  /// Also wire the new block's `out` into this input (`(block, port)`): a
  /// point of the Tree tab dropped on a field.
  final (String, String)? into;

  @override
  AppState? reduce() {
    final d = flowEditor.draft;
    if (d == null) {
      return null;
    }
    final t = flowEditor.allTypes.where((t) => t.type == type).firstOrNull;
    // An instance is named after its block (`mean1`), not `block_mean1`.
    final base = (blockNameOf(type) ?? type).replaceAll(
      RegExp('[^A-Za-z0-9_]'),
      '_',
    );
    var n = 1;
    while (d.blocks.containsKey('$base$n')) {
      n++;
    }
    final id = '$base$n';
    final defaults = <String, Object?>{
      for (final p in t?.params ?? const IListConst<ParamSpec>([]))
        if (p.choices.isNotEmpty && p.defaultValue != null)
          p.name: p.defaultValue,
    };
    unawaited(dispatchAndWait(ValidateFlowAction()));
    final into = this.into;
    return state.copyWith.flowEditor(
      // A point dropped on a key field: its wire needs a scope too.
      scopePrompt:
          into != null && scopeAsked(flowEditor.allTypes, d, into.$1, into.$2)
          ? into.$1
          : flowEditor.scopePrompt,
      draft: pinBound(
        flowEditor.allTypes,
        d.copyWith(
          edges: into == null
              ? d.edges
              : d.edges
                    .removeWhere((e) => e.to == into.$1 && e.toPort == into.$2)
                    .add(
                      FlowEdge(
                        from: id,
                        fromPort: 'out',
                        to: into.$1,
                        toPort: into.$2,
                      ),
                    ),
          blocks: d.blocks.add(
            id,
            FlowBlock(
              id: id,
              type: type,
              cfg: <String, Object?>{...defaults, ...cfg}.lock,
              pins: pins.lock,
              x: x,
              y: y,
            ),
          ),
        ),
      ),
      selectedBlock: into == null ? id : flowEditor.selectedBlock,
      selection: into == null ? {id}.toISet() : flowEditor.selection,
      dirty: true,
      undo: undoPush(flowEditor.undo, d, tag: tag, lastTag: flowEditor.undoTag),
      redo: const IListConst([]),
      undoTag: null,
    );
  }
}
