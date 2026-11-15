import 'package:async_redux/async_redux.dart';

import '../../../wyrm/mappers/flow_canvas.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import 'remove_blocks_action.dart';
import 'write_clipboard_action.dart';

/// Copy (or, with [cut], Cut) of the selected blocks: into the editor's own
/// clipboard (it lasts from one flow to the next) and, as the same JSON,
/// onto the system's (another window pastes it). Nothing selected: nothing
/// happens.
class CopyBlocksAction extends Action {
  CopyBlocksAction({this.cut = false});

  final bool cut;

  @override
  AppState? reduce() {
    final d = flowEditor.draft;
    final ids = flowEditor.selection.unlock;
    final text = d == null ? null : clipTextOf(d, ids);
    if (text == null) {
      return null;
    }
    // The system's clipboard is written on its own; nothing waits for it.
    _start(WriteClipboardAction(text));
    if (cut) {
      dispatchSync(RemoveBlocksAction(ids), notify: false);
    }
    return state.copyWith.flowEditor(clipboard: text);
  }

  /// Starts [action] and does not wait for it: it brings its own state
  /// (and its own waiting state, where it has one).
  void _start(ReduxAction<AppState> action) => dispatch(action);
}
