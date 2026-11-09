import '../../app_state.dart';
import '../../common/action.dart';

class SetDraftAction extends Action {
  SetDraftAction(this.draft);

  final String? draft;

  @override
  AppState reduce() => state.copyWith.assistant(draft: draft);
}
