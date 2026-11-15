import 'package:async_redux/async_redux.dart';
import 'package:models/flow_edit.dart';

import '../../../wyrm/mappers/flow_blocks.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import 'copy_blocks_action.dart';
import 'enter_block_action.dart';
import 'paste_blocks_action.dart';
import 'paste_blocks_at_action.dart';
import 'redo_flow_action.dart';
import 'remove_blocks_action.dart';
import 'set_selected_block_action.dart';
import 'set_viewed_field_action.dart';
import 'tidy_flow_action.dart';
import 'undo_flow_action.dart';

/// An edit of the canvas, from a key or from its context menu (spec §13),
/// on the selection as it is when the edit comes: the clipboard and the
/// history change without the page being built again. A paste lands at
/// ([x], [y]) when the pointer gave a place.
class FlowEditAction extends Action {
  FlowEditAction(this.edit, {this.x, this.y});

  final FlowEdit edit;
  final double? x;
  final double? y;

  @override
  AppState? reduce() {
    final ed = flowEditor;
    final d = ed.draft;
    if (d == null) {
      return null;
    }
    final ids = ed.selection.unlock;
    switch (edit) {
      case FlowEdit.copy:
        dispatchSync(CopyBlocksAction());
      case FlowEdit.cut:
        dispatchSync(CopyBlocksAction(cut: true));
      case FlowEdit.paste:
        // It reads the system clipboard first; it brings its own state.
        _start(PasteBlocksAtAction(x: x, y: y));
      case FlowEdit.duplicate:
        dispatchSync(PasteBlocksAction.duplicate(d, ids));
      case FlowEdit.delete:
        dispatchSync(RemoveBlocksAction(ids));
      case FlowEdit.undo:
        dispatchSync(UndoFlowAction());
      case FlowEdit.redo:
        dispatchSync(RedoFlowAction());
      case FlowEdit.escape:
        // The viewer first, then the selection.
        if (ed.viewedField != null) {
          dispatchSync(SetViewedFieldAction(null));
        } else {
          dispatchSync(SetSelectedBlockAction(null));
        }
      case FlowEdit.tidy:
        dispatchSync(TidyFlowAction());
      case FlowEdit.editCustomBlock:
        final one = ids.length == 1 ? d.blocks[ids.single] : null;
        if (blockNameOf(one?.type) case final name?) {
          dispatchSync(EnterBlockAction(name, instance: one!.id));
        }
    }
    return null;
  }

  /// Starts [action] and does not wait for it: it brings its own state
  /// (and its own waiting state, where it has one).
  void _start(ReduxAction<AppState> action) => dispatch(action);
}
