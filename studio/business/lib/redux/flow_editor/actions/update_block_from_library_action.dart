import 'dart:async';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/error_kind.dart';

import '../../../wyrm/calls.dart';
import '../../../wyrm/decode/block_library.dart';
import '../../../wyrm/decode/decoded.dart';
import '../../../wyrm/failures.dart';
import '../../../wyrm/mappers/flow_blocks.dart';
import '../../../wyrm/mappers/flow_canvas.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import 'validate_flow_action.dart';

/// `Update from library`: the flow's copy of block [name] becomes the
/// library's newest version (`get_block`), for every instance of it. The
/// blocks it uses are copied when the flow has none of that name. An
/// instance loses the wires and constants of a port the new version does
/// not have.
class UpdateBlockFromLibraryAction extends Action {
  UpdateBlockFromLibraryAction(this.name);

  final String name;

  @override
  Future<AppState?> reduce() async {
    final root = site.root;
    if (root == null || flowEditor.frames.isNotEmpty) {
      return null;
    }
    final answer = switch (libraryBlockOf(
      await askOne(deps.wyrm, '$root/dataflows', 'get_block', nameArgs(name)),
    )) {
      Valid(:final value) => value,
      Invalid(:final field, :final reason) => throw StudioException.said(
        ErrorKind.broker,
        'The library block $name is not one Studio reads: $field: $reason.',
        key: '$root/dataflows',
        call: 'get_block',
        thing: name,
      ),
    };
    final d = flowEditor.draft;
    if (d == null || flowEditor.frames.isNotEmpty) {
      return null;
    }
    final copied = withLibraryBlock(
      d,
      name,
      answer.def,
      version: answer.version,
      requires: answer.requires,
      replace: true,
    );
    // Through the inside's own fold, so instances drop what is gone.
    final inner = insideDraftOf(copied, name);
    final next = inner == null ? copied : foldInside(copied, name, inner);
    unawaited(dispatchAndWait(ValidateFlowAction()));
    return state.copyWith.flowEditor(
      draft: next,
      dirty: true,
      undo: undoPush(flowEditor.undo, d),
      redo: const IListConst([]),
      undoTag: null,
    );
  }
}
