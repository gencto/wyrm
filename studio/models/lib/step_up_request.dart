import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'step_up_line.dart';

part 'step_up_request.freezed.dart';

/// A request the gateway refused with `confirm_required`, waiting in the
/// step-up dialog (ADR 0050 §1.3, board `UnlockStepUp`).
@freezed
abstract class StepUpRequest with _$StepUpRequest {
  const factory StepUpRequest({
    /// What is being applied, in order.
    @Default(IListConst([])) IList<StepUpLine> lines,

    /// The device key or the password is being checked.
    @Default(false) bool busy,

    /// Confirmed: the request goes again.
    @Default(false) bool done,

    /// The last try failed: `bad_password`, a cancelled prompt, …
    String? error,

    /// The session has no device key here, or it stopped working: the
    /// password is the only way.
    @Default(false) bool passwordOnly,
  }) = _StepUpRequest;
}
