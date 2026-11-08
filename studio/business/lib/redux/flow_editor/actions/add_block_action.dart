import 'dart:async';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/flow_block.dart';
import 'package:models/flow_edge.dart';
import 'package:models/param_spec.dart';

import '../../app_state.dart';
import '../../common/action.dart';
import 'validate_flow_action.dart';

/// Adds a block of [type] at ([x], [y]) with the defaults of its choice
/// parameters (and [cfg] over them: a point dragged from the tree gives its
/// key) under a fresh id (`<type><n>`), and selects it.
///
/// Other defaults stay out of the definition: the block shows them as the
/// values of its fields, and the engine applies them itself. Writing them
/// would change what a block means (`scale` with `k` and a range at once is
/// refused).
class AddBlockAction extends Action {
  AddBlockAction(
    this.type,
    this.x,
    this.y, {
    this.cfg = const {},
    this.into,
  });

  final String type;
  final double x;
  final double y;
  final Map<String, Object?> cfg;

  /// Also wire the new block's `out` into this input (`(block, port)`): a
  /// point of the Tree tab dropped on a field.
  final (String, String)? into;

  @override
  AppState? reduce() {
    final d = flowEditor.draft;
    if (d == null) {
      return null;
    }
    final t = flowEditor.types.where((t) => t.type == type).firstOrNull;
    final base = type.replaceAll(RegExp('[^A-Za-z0-9_]'), '_');
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
      draft: d.copyWith(
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
            x: x,
            y: y,
          ),
        ),
      ),
      selectedBlock: into == null ? id : flowEditor.selectedBlock,
      dirty: true,
    );
  }
}
