import 'package:async_redux/async_redux.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../../wyrm/calls.dart';
import '../../../wyrm/decode/block_library.dart';
import '../../../wyrm/mappers/flow_blocks.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import 'retrieve_block_library_action.dart';

/// `Save to library`: custom block [name] of this flow goes to the site's
/// library (`dataflows` ▸ `put_block {name, def}`, level config; each put
/// is the next version). The blocks it uses that the library does not hold
/// go first: the library refuses a block that uses one it has not. The
/// flow's copy is then marked with the version it was saved as, and the
/// library read again, in one state: the palette never shows the mark
/// without the library's new version.
class SaveBlockToLibraryAction extends Action with NonReentrant, WaitingAction {
  SaveBlockToLibraryAction(this.name);

  final String name;

  @override
  Future<AppState?> reduce() async {
    final root = site.root;
    final flow = flowEditor.root;
    if (root == null || flow == null) {
      return null;
    }
    final defs = blockDefsOf(flow);
    final held = {for (final b in flowEditor.library) b.name};
    var version = 0;
    try {
      for (final n in blockClosure(defs, [name])) {
        if (n != name && held.contains(n)) {
          continue;
        }
        final answer = await invokeOne(
          deps.wyrm,
          '$root/dataflows',
          'put_block',
          putBlockArgs(n, defs[n]!),
        );
        if (n == name) {
          version = putBlockVersionOf(answer).orWarn('put_block $n') ?? 0;
        }
      }
    } on WyrmException {
      // A block it uses may have gone in before the refusal.
      _readAgain();
      rethrow;
    }
    final read = await readLibrary(deps.wyrm, root);
    // Only the flow's own draft carries the mark (not an inside view).
    final d = flowEditor.draft;
    final own = blockDefsOf(d)[name];
    if (d == null || own == null || flowEditor.frames.isNotEmpty) {
      return state.copyWith.flowEditor(
        library: read.library,
        libraryOff: read.off,
      );
    }
    return state.copyWith.flowEditor(
      library: read.library,
      libraryOff: read.off,
      draft: withBlockDefs(d, {
        ...blockDefsOf(d),
        name: own.copyWith(libraryVersion: version),
      }),
    );
  }

  /// The library read again; nothing waits for it.
  void _readAgain() => dispatch(RetrieveBlockLibraryAction());
}
