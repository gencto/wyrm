import 'dart:async';

import '../../../wyrm/mappers/flow_fields.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import 'validate_flow_action.dart';

/// The − and + of a block with variable inputs (`add`, `if`, `expression`):
/// adds the next input, or removes the last one with every edge into it or
/// out of its echo, never below the type's minimum.
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
    if (v == null || (!add && v.names.length <= v.min)) {
      return null;
    }
    final names = add
        ? [...v.names, v.next]
        : v.names.sublist(0, v.names.length - 1);
    final gone = add ? null : '${v.prefix}${v.names.last}';
    unawaited(dispatchAndWait(ValidateFlowAction()));
    return state.copyWith.flowEditor(
      draft: d.copyWith(
        blocks: d.blocks.add(
          id,
          b.copyWith(cfg: b.cfg.add(v.param, names)),
        ),
        edges: gone == null
            ? d.edges
            : d.edges.removeWhere(
                (e) =>
                    (e.to == id && e.toPort == gone) ||
                    (e.from == id && e.fromPort == gone),
              ),
      ),
      dirty: true,
    );
  }
}
