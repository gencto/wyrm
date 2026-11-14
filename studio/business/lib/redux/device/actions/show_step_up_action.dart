import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/step_up_line.dart';
import 'package:models/step_up_request.dart';

import '../../app_state.dart';
import '../../common/action.dart';

/// The gateway refused a request with `confirm_required` (ADR 0050 §1.3):
/// the step-up dialog opens with what is being applied (board
/// `UnlockStepUp`). Dispatched by the step-up gate of `AppDependencies`,
/// which holds the request until `ConfirmStepUpAction` or
/// `CancelStepUpAction` ends it.
class ShowStepUpAction extends Action {
  ShowStepUpAction(this.lines);

  final List<StepUpLine> lines;

  @override
  AppState reduce() => state.copyWith.device(
    stepUp: StepUpRequest(
      lines: lines.lock,
      // Without a key that can sign here, the password is the only way.
      passwordOnly: !_canSign,
    ),
  );

  bool get _canSign =>
      state.device.available &&
      state.device.keyId != null &&
      state.device.deviceId != null &&
      !state.device.stale;
}
