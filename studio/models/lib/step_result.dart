import 'package:freezed_annotation/freezed_annotation.dart';

part 'step_result.freezed.dart';

@freezed
abstract class StepResult with _$StepResult {
  /// What a run did with one step (`~state.plan[n].result`).
  const factory StepResult({
    /// `ok`, `failed` or `skipped`.
    required String status,
    @Default('') String message,
    DateTime? time,
  }) = _StepResult;
}
