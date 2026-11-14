import '../../app_state.dart';
import '../../common/action.dart';

/// `Cancel` in the step-up dialog: the refused request fails with the
/// gateway's refusal, and nothing is applied.
class CancelStepUpAction extends Action {
  @override
  AppState reduce() {
    deps.endStepUp(confirmed: false);
    return state.copyWith.device(stepUp: null);
  }
}
