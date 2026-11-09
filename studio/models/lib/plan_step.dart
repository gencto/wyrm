import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'plan_step.freezed.dart';

@freezed
abstract class PlanStep with _$PlanStep {
  /// One step of an agent plan (`tasks/<id>` `~state` `plan[]`).
  const factory PlanStep({
    /// `set` or `invoke`.
    required String op,
    required String key,
    String? action,
    @Default(IMapConst({})) IMap<String, Object?> args,

    /// `read`, `write` or `config`.
    @Default('write') String level,
    @Default(false) bool approval,
    String? reason,
  }) = _PlanStep;
}
