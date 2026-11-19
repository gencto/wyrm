import 'package:freezed_annotation/freezed_annotation.dart';

import 'undo_kind.dart';

part 'undo_tag.freezed.dart';

/// What an edit of the flow editor was, for its history (flow-editor.md
/// §13): two edits in a row with the same tag are one step (typing in one
/// field, nudging with the arrows).
@freezed
abstract class UndoTag with _$UndoTag {
  const factory UndoTag(
    UndoKind kind, {

    /// The block the edit changed; empty for a nudge.
    @Default('') String block,

    /// The parameter or the operand port it typed into.
    @Default('') String name,
  }) = _UndoTag;
}
