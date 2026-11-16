import '../../app_state.dart';
import '../../common/action.dart';
import 'validate_flow_action.dart';

/// Names the flow being made ([id] is its key segment, `[A-Za-z0-9_]+`;
/// what is typed around it is dropped).
class NewFlowAction extends Action {
  NewFlowAction(String typed) : id = typed.trim();

  final String id;

  @override
  AppState? reduce() {
    final d = flowEditor.draft;
    if (d == null) {
      return null;
    }
    _validate();
    return state.copyWith.flowEditor(
      flowId: id,
      draft: d.copyWith(id: id),
      dirty: true,
    );
  }

  /// The engine checks the draft again once the edits settle
  /// ([ValidateFlowAction] is debounced and brings its own state); this
  /// edit does not wait for it.
  void _validate() => dispatch(ValidateFlowAction());
}
