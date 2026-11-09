import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import '../../app_state.dart';
import '../../common/action.dart';

/// Selects blocks on the canvas (flow-editor.md §13): [ids] alone, or
/// added to the selection ([add]: Shift with a marquee), or each one
/// switched in or out of it ([toggle]: Shift- or Cmd/Ctrl-click). The
/// inspector shows a block when exactly one is selected (`selectedBlock`).
class SelectBlocksAction extends Action {
  SelectBlocksAction(this.ids, {this.add = false, this.toggle = false});

  final Iterable<String> ids;
  final bool add;
  final bool toggle;

  @override
  AppState? reduce() {
    final blocks = flowEditor.draft?.blocks;
    final given = {
      for (final id in ids)
        if (blocks?.containsKey(id) ?? false) id,
    };
    final now = flowEditor.selection;
    final next = toggle
        ? now.removeAll(given).addAll(given.where((id) => !now.contains(id)))
        : (add ? now.addAll(given) : given.toISet());
    final one = next.length == 1 ? next.single : null;
    if (next == now && one == flowEditor.selectedBlock) {
      return null;
    }
    return state.copyWith.flowEditor(selection: next, selectedBlock: one);
  }
}
