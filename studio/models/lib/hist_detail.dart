import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'hist_point.dart';

part 'hist_detail.freezed.dart';

/// The rows of a trend's window read finer than its range (spec trend.md
/// §4): [from]…[to] at [step] (`raw`, `1m`, `5m`, …), per key the line
/// ([points], `avg` or raw) and, for a rollup, the buckets' extremes.
@freezed
abstract class HistDetail with _$HistDetail {
  const factory HistDetail({
    required DateTime from,
    required DateTime to,
    required String step,
    @Default(IMapConst({})) IMap<String, IList<HistPoint>> points,
    @Default(IMapConst({})) IMap<String, IList<HistPoint>> low,
    @Default(IMapConst({})) IMap<String, IList<HistPoint>> high,
  }) = _HistDetail;
}
