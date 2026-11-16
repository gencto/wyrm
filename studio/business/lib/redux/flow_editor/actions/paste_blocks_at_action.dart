import 'package:async_redux/async_redux.dart';

import '../../app_state.dart';
import '../../common/action.dart';
import 'paste_blocks_action.dart';
import 'write_clipboard_action.dart';

/// Paste at ([x], [y]) (the pointer; else the canvas's corner): what the
/// system clipboard holds, and a text that is not blocks pastes nothing.
/// Only where there is no system clipboard (or it is empty) the editor's
/// own copy is pasted.
///
/// Started by a key that does not wait for it, so it reads in
/// [clipboardQueue] (after every copy dispatched before it) and pastes
/// only into the flow that was open when it was pressed.
class PasteBlocksAtAction extends Action with Sequential<AppState> {
  PasteBlocksAtAction({this.x, this.y});

  final double? x;
  final double? y;

  /// The flow open when the paste was pressed.
  String? _flow;

  @override
  Object? sequentialKeyParams() => clipboardQueue;

  @override
  Future<void> before() {
    // At the dispatch, not at its turn in the queue (Sequential: code
    // before `super.before()` runs at once).
    _flow = flowEditor.flowId;
    return super.before();
  }

  @override
  Future<AppState?> reduce() async {
    final text = await deps.clipboard.read();
    if (flowEditor.flowId != _flow || flowEditor.draft == null) {
      return null;
    }
    final own = flowEditor.clipboard;
    dispatchSync(
      PasteBlocksAction(
        text == null || text.isEmpty ? own : text,
        x ?? 60,
        y ?? 60,
      ),
    );
    return null;
  }
}
