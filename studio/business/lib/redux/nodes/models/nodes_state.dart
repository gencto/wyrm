import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:models/hist_point.dart';
import 'package:models/node_detail.dart';
import 'package:models/node_info.dart';

part 'nodes_state.freezed.dart';

@freezed
abstract class NodesState with _$NodesState {
  const factory NodesState({
    @Default(IMapConst({})) IMap<String, NodeInfo> table,
    @Default(IListConst([])) IList<String> view,
    @Default(ISetConst({})) ISet<String> expanded,
    String? selectedNode,
    @Default(IMapConst({})) IMap<String, IList<String>> results,
    @Default('points') String tab,
    String? action,
    @Default('1h') String historyRange,
    @Default(IMapConst({})) IMap<String, NodeDetail> detail,
    @Default(IListConst([])) IList<HistPoint> history,
    String? historyKey,
  }) = _NodesState;
}
