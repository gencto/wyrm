import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:models/action_answer.dart';
import 'package:models/audit_entry.dart';
import 'package:models/explorer_tab.dart';
import 'package:models/hist_point.dart';
import 'package:models/hist_window.dart';
import 'package:models/history_range.dart';
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
    @Default(ExplorerTab.points) ExplorerTab tab,
    String? action,
    @Default(HistoryRange.hour) HistoryRange historyRange,
    @Default(IMapConst({})) IMap<String, NodeDetail> detail,
    @Default(IListConst([])) IList<HistPoint> history,
    String? historyKey,
    String? point,
    @Default(ISetConst({})) ISet<String> checked,
    String? anchor,
    @Default('') String treeFilter,
    @Default('') String pointFilter,
    @Default(ISetConst({})) ISet<String> marked,
    @Default(IListConst([])) IList<AuditEntry> audit,
    @Default(ISetConst({})) ISet<String> listed,
    String? viewedPoint,
    String? historyFailed,
    @Default(IMapConst({})) IMap<String, String> listFailed,
    @Default(IMapConst({})) IMap<String, String> metaFailed,
    HistWindow? historyWindow,
    DateTime? historyAt,
    @Default(IMapConst({})) IMap<String, ActionAnswer> answers,
    IList<String>? watching,
    String? menu,
    String? menuAsked,
  }) = _NodesState;
}
