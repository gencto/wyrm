import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'update_report.freezed.dart';

@freezed
abstract class UpdateReport with _$UpdateReport {
  /// `sys/packages/<name>/last_update`: the last update or rollback of a
  /// package (ADR 0048 §1).
  const factory UpdateReport({
    @Default('') String from,
    @Default('') String to,

    /// Unix seconds, the broker's clock.
    @Default(0) int at,

    /// `checking` while the health check runs, then `ok`, `rolled_back` or
    /// `failed`.
    @Default('') String result,
    @Default(0) int kept,
    @Default(0) int added,
    @Default(0) int gone,

    /// `<link>/<path>`, at most 200 each.
    @Default(IListConst([])) IList<String> newKeys,
    @Default(IListConst([])) IList<String> goneKeys,
    @Default('') String reason,
    @Default(IListConst([])) IList<String> links,
    @Default(false) bool changesState,
    @Default(false) bool restorePoint,
  }) = _UpdateReport;
}
