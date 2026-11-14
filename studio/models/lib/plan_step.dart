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

    /// The schema of [args] is known (the `~meta` of the step's node was
    /// read). When it is not (`check: at_run`, the node does not exist
    /// yet; or the meta could not be read), any argument may be a secret:
    /// all are masked until the person reveals them, and none is written
    /// to a file.
    @Default(true) bool argsKnown,

    /// `wait`/`expect`: the timeout; `sleep`: its length. Seconds.
    double? seconds,

    /// `read`, `write` or `config`.
    @Default('write') String level,

    /// The step needs a human token.
    @Default(false) bool approval,

    /// `now` (checked against the live tree) or `at_run`.
    @Default('now') String check,

    /// The link's own finding about the step (a checked conclusion).
    String? warn,

    /// The model's words about the step (`model_warn`): never shown as a
    /// check of the link.
    String? modelWarn,

    /// The steps (by number) this one needs.
    @Default(IListConst([])) IList<int> after,
    String? reason,
    StepResult? result,
  }) = _PlanStep;
}
