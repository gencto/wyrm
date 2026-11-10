import 'dart:async';

import 'package:wyrm_client/wyrm_client.dart';

import '../../../wyrm/calls.dart';
import '../../../wyrm/mappers/flow_blocks.dart';
import '../../../wyrm/mappers/values.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import 'retrieve_block_library_action.dart';

/// `Save to library`: custom block [name] of this flow goes to the site's
/// library (`dataflows` ▸ `put_block {name, def}`, level config; each put
/// is the next version). The blocks it uses that the library does not hold
/// go first: the library refuses a block that uses one it has not. The
/// flow's copy is then marked with the version it was saved as.
class SaveBlockToLibraryAction extends Action {
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
    for (final n in blockClosure(defs, [name])) {
      if (n != name && held.contains(n)) {
        continue;
      }
      final answer = await invokeOne(
        deps.wyrm,
        '$root/dataflows',
        'put_block',
        Value.from({'name': n, 'def': libraryDefOf(defs[n]!)}),
      );
      if (n == name) {
        version = integer(answer['version']) ?? 0;
      }
    }
    // Only the flow's own draft carries the mark (not an inside view).
    final d = flowEditor.draft;
    final own = blockDefsOf(d)[name];
    if (d == null || own == null || flowEditor.frames.isNotEmpty) {
      return state.copyWith.flowEditor(message: 'saved $name');
    }
    return state.copyWith.flowEditor(
      draft: withBlockDefs(d, {
        ...blockDefsOf(d),
        name: withLibraryVersion(own, version),
      }),
      message: 'saved $name as version $version',
    );
  }

  @override
  void after() {
    super.after();
    unawaited(dispatchAndWait(RetrieveBlockLibraryAction()));
  }
}
