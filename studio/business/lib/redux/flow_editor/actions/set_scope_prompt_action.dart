import '../../app_state.dart';
import '../../common/action.dart';

class SetScopePromptAction extends Action {
  SetScopePromptAction(this.scopePrompt);

  final String? scopePrompt;

  @override
  AppState reduce() => state.copyWith.flowEditor(scopePrompt: scopePrompt);
}
