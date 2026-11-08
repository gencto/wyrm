import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:models/flow_draft.dart';
import 'package:models/live_value.dart';
import 'package:models/node_type.dart';

part 'flow_editor_state.freezed.dart';

@freezed
abstract class FlowEditorState with _$FlowEditorState {
  const factory FlowEditorState({
    String? flowId,
    FlowDraft? draft,
    @Default(false) bool dirty,
    @Default(IListConst([])) IList<String> problems,
    String? selectedBlock,
    @Default(IListConst([])) IList<NodeType> types,
    @Default(0) int version,
    String? state,
    String? message,
    @Default('blocks') String palette,
    @Default(IMapConst({})) IMap<String, LiveValue> ports,
    FlowDraft? deployed,
    String? watchRefused,
  }) = _FlowEditorState;
}
