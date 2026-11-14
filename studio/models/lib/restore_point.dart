import 'package:freezed_annotation/freezed_annotation.dart';

part 'restore_point.freezed.dart';

@freezed
abstract class RestorePoint with _$RestorePoint {
  /// One row of `sys/links/<id>/restore_points` (ADR 0048 §1.3).
  const factory RestorePoint({
    /// Unix seconds.
    @Default(0) int at,

    /// The version the link ran; empty for a point taken before a restore
    /// from a backup.
    @Default('') String version,

    /// Bytes.
    @Default(0) int size,
  }) = _RestorePoint;
}
