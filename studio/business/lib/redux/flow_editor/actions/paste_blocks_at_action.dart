import '../../app_state.dart';
import '../../common/action.dart';
import 'paste_blocks_action.dart';

/// Paste at ([x], [y]) (the pointer; else the canvas's corner): what the
/// system clipboard holds, and a text that is not blocks pastes nothing.
/// Only where there is no system clipboard (or it is empty) the editor's
/// own copy is pasted.
class PasteBlocksAtAction extends Action {
  PasteBlocksAtAction({this.x, this.y});

  final double? x;
  final double? y;

  @override
  Future<AppState?> reduce() async {
    final text = await deps.clipboard.read();
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
