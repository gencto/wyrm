import 'package:freezed_annotation/freezed_annotation.dart';

part 'step_up_line.freezed.dart';

/// One change a step-up confirms (board `UnlockStepUp`): its level badge,
/// what it does and the key it is on.
@freezed
abstract class StepUpLine with _$StepUpLine {
  const factory StepUpLine({
    /// `config` or `write`.
    required String level,
    required String text,
    @Default('') String key,
  }) = _StepUpLine;
}
