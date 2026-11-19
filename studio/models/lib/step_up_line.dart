import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:wyrm_core/wyrm_core.dart' show Perm;

import 'step_up_deed.dart';

part 'step_up_line.freezed.dart';

/// One change a step-up confirms (board `UnlockStepUp`): its level badge,
/// what it does and the key it is on.
@freezed
abstract class StepUpLine with _$StepUpLine {
  const factory StepUpLine({
    /// The level the change needs: its badge (`config` coral, else grey).
    required Perm level,

    /// What it does.
    required StepUpDeed deed,
    @Default('') String key,
  }) = _StepUpLine;
}
