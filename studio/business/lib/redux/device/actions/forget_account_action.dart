import 'package:models/unlock_stage.dart';

import '../../app_state.dart';
import '../../common/action.dart';

/// `Another account or gateway`: the log-in form as login.md has it, with
/// the fields to change. The key of the account stays; it is offered again
/// when that gateway and user are in the form at the next start.
class ForgetAccountAction extends Action {
  @override
  AppState reduce() => state.copyWith(
    device: state.device.copyWith(
      stage: UnlockStage.none,
      refusal: null,
      reason: null,
      autoPrompted: true,
    ),
    login: state.login.copyWith(password: null, failure: null),
  );
}
