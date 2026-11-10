import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'flow_draft.dart';

part 'flow_frame.freezed.dart';

/// What the flow editor left to show the inside of a custom block
/// (flow-editor.md §20): the draft that was on the canvas, its history, the
/// block opened and the instance it was opened from.
@freezed
abstract class FlowFrame with _$FlowFrame {
  const factory FlowFrame({
    /// The draft the canvas showed: the flow, or the block one level up.
    required FlowDraft draft,

    /// The custom block whose inside is shown now.
    required String block,

    /// The instance it was opened from: its inner nodes' live values are
    /// the rows `<instance>/<inner>`. Null: opened from the palette.
    String? instance,
    @Default(IListConst([])) IList<FlowDraft> undo,
    @Default(IListConst([])) IList<FlowDraft> redo,
    @Default(ISetConst({})) ISet<String> selection,
  }) = _FlowFrame;
}
