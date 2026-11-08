import 'package:freezed_annotation/freezed_annotation.dart';

part 'hist_point.freezed.dart';

/// One recorded value of a point (`~val?history=`).
@freezed
abstract class HistPoint with _$HistPoint {
  const factory HistPoint({
    required DateTime time,

    /// A number when the value is one (a bool as 0/1), else null.
    num? value,

    /// The value as text.
    @Default('') String text,

    /// `good`, `uncertain`, `bad`; null for a rollup row.
    String? quality,
  }) = _HistPoint;
}
