import 'dart:async';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../../wyrm/calls.dart';
import '../../../wyrm/mappers/flow_blocks.dart';
import '../../../wyrm/mappers/flow_canvas.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import 'add_block_action.dart';

/// A block of the site's library dropped on the canvas at ([x], [y]): the
/// flow COPIES it (`dataflows` ▸ `get_block {name}`: its definition and the
/// library blocks it uses go into the definition's `blocks`, ADR 0040 §3)
/// and gets one instance of it. A block of that name the flow already has
/// is used as the flow has it; `Update from library` replaces it.
class PlaceLibraryBlockAction extends Action {
  PlaceLibraryBlockAction(this.name, this.x, this.y);

  final String name;
  final double x;
  final double y;

  @override
  Future<AppState?> reduce() async {
    final root = site.root;
    if (root == null || flowEditor.draft == null) {
      return null;
    }
    final answer = libraryBlockOf(
      await askOne(
        deps.wyrm,
        '$root/dataflows',
        'get_block',
        Value.from({'name': name}),
      ),
    );
    // The draft as it is now: the read took a while.
    final d = flowEditor.draft;
    if (d == null) {
      return null;
    }
    final next = withLibraryBlock(
      d,
      name,
      answer.def,
      version: answer.version,
      requires: answer.requires,
    );
    return state.copyWith.flowEditor(
      draft: next,
      dirty: true,
      undo: undoPush(flowEditor.undo, d),
      redo: const IListConst([]),
      undoTag: 'place:$name',
    );
  }

  @override
  void after() {
    super.after();
    // The instance, in the same step of the history as the copy.
    if (blockDefsOf(flowEditor.draft).containsKey(name)) {
      dispatchSync(
        AddBlockAction('$blockTypePrefix$name', x, y, tag: 'place:$name'),
      );
    }
  }
}
