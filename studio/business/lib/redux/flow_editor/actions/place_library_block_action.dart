import 'package:async_redux/async_redux.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/block_type.dart';
import 'package:models/error_hint.dart';
import 'package:models/error_kind.dart';
import 'package:models/unreadable_part.dart';

import '../../../wyrm/calls.dart';
import '../../../wyrm/decode/block_library.dart';
import '../../../wyrm/decode/decoded.dart';
import '../../../wyrm/failures.dart';
import '../../../wyrm/mappers/flow_blocks.dart';
import '../../../wyrm/mappers/flow_canvas.dart';
import '../../app_state.dart';
import '../../common/action.dart';

/// A block of the site's library dropped on the canvas at ([x], [y]): the
/// flow COPIES it (`dataflows` ▸ `get_block {name}`: its definition and the
/// library blocks it uses go into the definition's `blocks`, ADR 0040 §3)
/// and gets one instance of it, selected, in one step of the history. A
/// block of that name the flow already has
/// is used as the flow has it; `Update from library` replaces it.
///
/// Started by a drop that does not wait for it: drops run one at a time in
/// the order they were made (each is a step of the history), and a block
/// whose answer comes after its flow was left is not placed.
class PlaceLibraryBlockAction extends Action with Sequential<AppState> {
  PlaceLibraryBlockAction(this.name, this.x, this.y);

  final String name;
  final double x;
  final double y;

  /// The flow open when the block was dropped.
  String? _flow;

  @override
  Object? sequentialKeyParams() => runtimeType;

  @override
  Future<void> before() {
    // At the drop, not at its turn in the queue.
    _flow = flowEditor.flowId;
    return super.before();
  }

  @override
  Future<AppState?> reduce() async {
    final root = site.root;
    if (root == null ||
        flowEditor.draft == null ||
        flowEditor.flowId != _flow) {
      return null;
    }
    final answer = switch (libraryBlockOf(
      await askOne(deps.wyrm, '$root/dataflows', 'get_block', nameArgs(name)),
    )) {
      Valid(:final value) => value,
      final Invalid<Object?> bad => throw StudioException.hinted(
        ErrorKind.broker,
        ErrorHint.unreadable(
          UnreadablePart.libraryBlock,
          name: name,
          field: loggedField('$root/dataflows ▸ get_block $name', bad),
        ),
        key: '$root/dataflows',
        call: const .known(.getBlock),
        thing: name,
      ),
    };
    // The draft as it is now: the read took a while, and the flow may
    // have been left.
    final d = flowEditor.draft;
    if (d == null || flowEditor.flowId != _flow || site.root != root) {
      return null;
    }
    final copied = withLibraryBlock(
      d,
      name,
      answer.def,
      version: answer.version,
      requires: answer.requires,
    );
    if (!blockDefsOf(copied).containsKey(name)) {
      return null;
    }
    // The copy and its instance are one state and one step of the
    // history: the screen never draws the copy without its instance.
    final types = typesWithBlocks(flowEditor.types, copied);
    final added = withNewBlock(types, copied, CustomType(name), x, y);
    return state.copyWith.flowEditor(
      draft: added.draft,
      selectedBlock: added.id,
      selection: {added.id}.toISet(),
      dirty: true,
      undo: undoPush(flowEditor.undo, d),
      redo: const IListConst([]),
      undoTag: null,
    );
  }
}
