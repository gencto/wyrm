import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
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
  }) = _NodesState;
}
