import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'flow_summary.freezed.dart';

@freezed
abstract class FlowSummary with _$FlowSummary {
  /// One flow of `dataflows/<id>`.
  const factory FlowSummary({
    required String id,
    int? version,
    String? deployedBy,
    @Default(false) bool draft,
    String? problem,
    @Default(IListConst([])) IList<String> reads,
    @Default(IListConst([])) IList<String> writes,
    @Default(0) int blocks,
    String? description,
    @Default(false) bool running,
  }) = _FlowSummary;
}
