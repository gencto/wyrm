import '../../../wyrm/calls.dart';
import '../../../wyrm/explorer.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import 'invoke_node_action.dart';
import 'retrieve_node_detail_action.dart';
import 'stage_invoke_action.dart';
import 'stage_value_action.dart';

/// The inspector's form, sent with [values] (docs/design/specs/errors.md
/// §3): the selected action staged (`config`) or run now, or a new value of
/// the point on screen staged — what the inspector shows when it is sent,
/// read here and not when the page was drawn. A run is this action's own
/// work, so a refusal of the input is its error and goes back to the form.
class SubmitInspectorAction extends Action with WaitingAction {
  SubmitInspectorAction(this.values);

  /// The form's values as action arguments.
  final Map<String, Object?> values;

  /// What was run: *Try again* runs it again, *Reload* reads its node.
  RunActionSubmit? _ran;

  /// The form shows its own wait (it awaits this action); no screen draws
  /// this one.
  @override
  bool get notifyBefore => false;

  @override
  Action? again() => switch (_ran) {
    final r? => InvokeNodeAction(
      r.key,
      r.action.name,
      values,
      clearedNames(r.action.params),
    ),
    null => null,
  };

  @override
  Action? reload() => switch (_ran) {
    final r? => RetrieveNodeDetailAction(r.key),
    null => null,
  };

  @override
  Future<AppState?> reduce() async {
    switch (ExplorerView(state).submit) {
      case StageActionSubmit(:final key, :final action, :final display):
        dispatchSync(
          StageInvokeAction(
            key,
            action.name,
            values,
            display: display,
            keepEmpty: clearedNames(action.params),
          ),
        );
        return null;
      case final RunActionSubmit r:
        _ran = r;
        return InvokeNodeAction.run(
          this,
          r.key,
          r.action.name,
          values,
          clearedNames(r.action.params),
        );
      case StageValueSubmit(:final key):
        if (values.containsKey(key)) {
          dispatchSync(StageValueAction.entered(key, values[key]));
        }
        return null;
      case NoSubmit():
        return null;
    }
  }
}
