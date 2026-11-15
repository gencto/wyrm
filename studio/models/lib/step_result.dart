import 'package:freezed_annotation/freezed_annotation.dart';

import 'step_status.dart';

part 'step_result.freezed.dart';

@freezed
abstract class StepResult with _$StepResult {
  /// What a run did with one step (`~state.plan[n].result`).
  const factory StepResult({
    required StepStatus status,
    @Default('') String message,

    /// The fixed word a refusal starts with (`out_of_range: …`), if any.
    String? code,
    DateTime? time,
  }) = _StepResult;
}
