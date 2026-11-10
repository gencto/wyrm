import 'dart:async';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/flow_edge.dart';

import '../../../wyrm/mappers/flow_blocks.dart';
import '../../../wyrm/mappers/flow_canvas.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import 'validate_flow_action.dart';

/// Wires `<from>.<fromPort>` to `<to>.<toPort>`; an input takes one wire,
/// so a wire already into it is replaced.
class ConnectPortsAction extends Action {
  ConnectPortsAction(this.from, this.fromPort, this.to, this.toPort);

  final String from;
  final String fromPort;
  final String to;
  final String toPort;

  @override
  AppState? reduce() {
    final d = flowEditor.draft;
    if (d == null || from == to) {
      return null;
    }
    unawaited(dispatchAndWait(ValidateFlowAction()));
    return state.copyWith.flowEditor(
      // A key that gets a wire needs a scope: the editor asks for it in
      // place (flow-editor.md §17).
      scopePrompt: scopeAsked(flowEditor.allTypes, d, to, toPort)
          ? to
          : flowEditor.scopePrompt,
      // A field that gets a wire is pinned to its block (spec §12).
      draft: pinBound(
        flowEditor.allTypes,
        d.copyWith(
          edges: d.edges
              .removeWhere((e) => e.to == to && e.toPort == toPort)
              .add(
                FlowEdge(
                  from: from,
                  fromPort: fromPort,
                  to: to,
                  toPort: toPort,
                ),
              ),
        ),
      ),
      dirty: true,
      undo: undoPush(flowEditor.undo, d),
      redo: const IListConst([]),
      undoTag: null,
    );
  }
}
