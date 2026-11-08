import 'dart:async';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/flow_block.dart';
import 'package:models/param_spec.dart';

import '../../app_state.dart';
import '../../common/action.dart';
import 'validate_flow_action.dart';

/// Adds a block of [type] at ([x], [y]) with its parameters' defaults (and
/// [cfg] over them: a point dragged from the tree gives its key) under a
/// fresh id (`<type>_<n>`), and selects it.
class AddBlockAction extends Action {
  AddBlockAction(this.type, this.x, this.y, {this.cfg = const {}});

  final String type;
  final double x;
  final double y;
  final Map<String, Object?> cfg;

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
        if (p.defaultValue != null) p.name: p.defaultValue,
    };
    unawaited(dispatchAndWait(ValidateFlowAction()));
    return state.copyWith.flowEditor(
      draft: d.copyWith(
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
      selectedBlock: id,
      dirty: true,
    );
  }
}
