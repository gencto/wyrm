import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'step_result.dart';

part 'plan_step.freezed.dart';

@freezed
abstract class PlanStep with _$PlanStep {
  /// One step of an agent plan (`tasks/<id>` `~state` `plan[]`, ADR 0049).
  const factory PlanStep({
    /// `set`, `invoke`, `wait`, `expect` or `sleep`.
    required String op,

    /// The node the step is about (empty for `sleep`).
    required String key,

    /// Its number in the plan, from 1.
    @Default(0) int n,
    String? action,

    /// `set`: `{value}`; `invoke`: its arguments; `expect`: the test
    /// (`equals`, `min`/`max`, `changes`).
    @Default(IMapConst({})) IMap<String, Object?> args,

    /// The names of [args] the action's `~meta` marks as secret (a
    /// password editor): never shown, never written to a file.
    @Default(ISetConst({})) ISet<String> secret,

    /// `wait`/`expect`: the timeout; `sleep`: its length. Seconds.
    double? seconds,

    /// `read`, `write` or `config`.
    @Default('write') String level,

    /// The step needs a human token.
    @Default(false) bool approval,

    /// `now` (checked against the live tree) or `at_run`.
    @Default('now') String check,
    String? warn,

    /// The steps (by number) this one needs.
    @Default(IListConst([])) IList<int> after,
    String? reason,
    StepResult? result,
  }) = _PlanStep;
}
