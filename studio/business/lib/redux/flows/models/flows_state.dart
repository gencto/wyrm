import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:models/flow_summary.dart';
import 'package:models/node_type.dart';

part 'flows_state.freezed.dart';

@freezed
abstract class FlowsState with _$FlowsState {
  const factory FlowsState({
    String? query,
    @Default(IListConst([])) IList<String> view,
    @Default(IMapConst({})) IMap<String, FlowSummary> table,
    String? selectedFlow,
    @Default(IMapConst({})) IMap<String, Object> defs,
    @Default(IListConst([])) IList<NodeType> blockTypes,
  }) = _FlowsState;
}
