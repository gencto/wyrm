import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:models/block_info.dart';
import 'package:models/field_id.dart';
import 'package:models/flow_draft.dart';
import 'package:models/flow_frame.dart';
import 'package:models/flow_problem.dart';
import 'package:models/library_off.dart';
import 'package:models/live_value.dart';
import 'package:models/node_type.dart';
import 'package:models/palette_tab.dart';
import 'package:models/undo_tag.dart';
import 'package:wyrm_client/wyrm_client.dart' show Status;

part 'flow_editor_state.freezed.dart';

@freezed
abstract class FlowEditorState with _$FlowEditorState {
  const factory FlowEditorState({
    String? flowId,
    FlowDraft? draft,
    @Default(false) bool dirty,
    @Default(IListConst([])) IList<FlowProblem> problems,
    String? selectedBlock,
    @Default(IListConst([])) IList<NodeType> types,
    @Default(0) int version,
    String? state,
    String? message,
    @Default(PaletteTab.blocks) PaletteTab palette,
    @Default(IMapConst({})) IMap<String, LiveValue> ports,
    FlowDraft? deployed,

    /// Why the broker refused the deployed flow's watch for good.
    Status? watchRefused,
    @Default(IMapConst({})) IMap<String, LiveValue> previewPorts,
    @Default(IMapConst({})) IMap<String, LiveValue> previewSinks,

    /// The broker's compiler refused the draft's preview.
    FlowProblem? previewError,

    /// Why the broker has no preview for this session.
    Status? previewOff,

    /// The field the value viewer shows.
    FieldAt? viewedField,
    @Default(ISetConst({})) ISet<String> selection,
    @Default(IListConst([])) IList<FlowDraft> undo,
    @Default(IListConst([])) IList<FlowDraft> redo,
    UndoTag? undoTag,
    String? clipboard,
    @Default('') String treeQuery,
    String? scopePrompt,
    @Default(IListConst([])) IList<FlowFrame> frames,
    @Default(IListConst([])) IList<BlockInfo> library,

    /// Why custom blocks are off; null once the library answered.
    LibraryOff? libraryOff,
  }) = _FlowEditorState;
}
