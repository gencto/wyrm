import 'dart:async';

import '../../../wyrm/mappers/flow_fields.dart';
import '../../../wyrm/mappers/flow_mapper.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import 'validate_flow_action.dart';

/// The − and + of a block with variable inputs (`add`, `if`, `expression`):
/// adds the next input, or removes the last one with every edge into it or
/// out of its echo and its constant, never below the type's minimum. A
/// block with paired inputs (`case`) adds or removes a pair.
class ResizeInputsAction extends Action {
  ResizeInputsAction(this.id, {required this.add});

  final String id;
  final bool add;

  @override
  AppState? reduce() {
    final d = flowEditor.draft;
    final b = d?.blocks[id];
    if (d == null || b == null) {
      return null;
    }
    final t = flowEditor.types.where((t) => t.type == b.type).firstOrNull;
    final v = variadicOf(t, b);
    final removes = v?.removes ?? const <String>[];
    if (v == null || (!add && removes.isEmpty)) {
      return null;
    }
    final names = add
        ? [...v.names, ...v.adds]
        : v.names.sublist(0, v.names.length - removes.length);
    final gone = {
      if (!add)
        for (final n in removes) '${v.prefix}$n',
    };
    unawaited(dispatchAndWait(ValidateFlowAction()));
    // A removed input's constant goes with it: the engine refuses a
    // `values` key that is no operand (ADR 0038 §7).
    final cfg = cfgWithoutOperands(b.cfg.add(v.param, names), gone);
    return state.copyWith.flowEditor(
      draft: d.copyWith(
        blocks: d.blocks.add(id, b.copyWith(cfg: cfg)),
        edges: gone.isEmpty
            ? d.edges
            : d.edges.removeWhere(
                (e) =>
                    (e.to == id && gone.contains(e.toPort)) ||
                    (e.from == id && gone.contains(e.fromPort)),
              ),
      ),
      dirty: true,
    );
  }
}
