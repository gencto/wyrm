import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import '../../../wyrm/mappers/flow_blocks.dart';
import '../../../wyrm/mappers/flow_canvas.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import 'validate_flow_action.dart';

/// The − and + of the inputs block or the outputs block of a custom
/// block's inside: one more declared port (`in1`, `out1`, …), or the last
/// one gone with its wires.
class ResizeBlockPortsAction extends Action {
  ResizeBlockPortsAction({required this.input, required this.add});

  final bool input;
  final bool add;

  @override
  AppState? reduce() {
    final d = flowEditor.draft;
    final next = d == null ? null : resizeBoundary(d, input: input, add: add);
    if (d == null || next == null) {
      return null;
    }
    _validate();
    return state.copyWith.flowEditor(
      draft: next,
      dirty: true,
      undo: undoPush(flowEditor.undo, d),
      redo: const IListConst([]),
      undoTag: null,
    );
  }

  /// The engine checks the draft again once the edits settle
  /// ([ValidateFlowAction] is debounced and brings its own state); this
  /// edit does not wait for it.
  void _validate() => dispatch(ValidateFlowAction());
}
