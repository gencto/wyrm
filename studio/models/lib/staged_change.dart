import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'staged_change.freezed.dart';

/// One edit staged in this session and applied with the others (design
/// canvas, *Design system* §01 "Stage, then apply once").
///
/// Applying it is either a `set` of [key] to [value], or an `invoke` of
/// [action] on [key] with [args].
@freezed
abstract class StagedChange with _$StagedChange {
  const factory StagedChange({
    /// Unique within the session.
    required String id,

    /// `Edit`, `Add` or `Remove`, as the review card says it.
    required String op,

    /// The node or value the change is on.
    required String key,

    /// What changes (`poll`, `value`, `params`).
    required String field,

    /// Shown in ember/new.
    required String to,

    /// Shown struck through.
    @Default('—') String from,

    /// `write` or `config`.
    @Default('write') String level,

    /// For a set: the value written to `key`.
    Object? value,

    /// For an invoke: the action and its arguments.
    String? action,
    @Default(IMapConst({})) IMap<String, Object?> args,
  }) = _StagedChange;
}
