import 'dart:async';
import 'dart:math' as math;

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/flow_draft.dart';

import '../../../wyrm/mappers/flow_canvas.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import 'validate_flow_action.dart';

/// Pastes the blocks of the clipboard [text] (`wyrm-flow-blocks/1`) with
/// the top-left corner of their bounding box at ([x], [y]) and selects
/// them. Their ids are made unique; the edges among them come along.
/// Anything that is not such a text changes nothing.
///
/// Duplicate is a paste of the selection's own text beside it.
class PasteBlocksAction extends Action {
  PasteBlocksAction(this.text, this.x, this.y);

  /// Duplicate: the blocks [ids] of [d] pasted beside the originals, one
  /// grid step down and to the right. Nothing to paste when none is in [d].
  factory PasteBlocksAction.duplicate(FlowDraft d, Set<String> ids) {
    final picked = [
      for (final b in d.blocks.values)
        if (ids.contains(b.id)) b,
    ];
    if (picked.isEmpty) {
      return PasteBlocksAction(null, 0, 0);
    }
    return PasteBlocksAction(
      clipTextOf(d, ids),
      picked.map((b) => b.x).reduce(math.min) + 20,
      picked.map((b) => b.y).reduce(math.min) + 20,
    );
  }

  final String? text;
  final double x;
  final double y;

  @override
  AppState? reduce() {
    final d = flowEditor.draft;
    final clip = clipOf(text).orWarn('paste');
    if (d == null || clip == null) {
      return null;
    }
    final (next, ids) = pasteClip(d, clip, x, y);
    unawaited(dispatchAndWait(ValidateFlowAction()));
    return state.copyWith.flowEditor(
      draft: pinBound(flowEditor.allTypes, next),
      selection: ids.toISet(),
      selectedBlock: ids.length == 1 ? ids.single : null,
      dirty: true,
      undo: undoPush(flowEditor.undo, d),
      redo: const IListConst([]),
      undoTag: null,
    );
  }
}
