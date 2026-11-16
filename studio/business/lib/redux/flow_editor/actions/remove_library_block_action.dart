import 'package:async_redux/async_redux.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../../wyrm/calls.dart';
import '../../../wyrm/decode/block_library.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import 'retrieve_block_library_action.dart';

/// Deletes block [name] from the site's library (`dataflows` ▸
/// `remove_block {name}`, level config). Flows that copied it keep their
/// copies. The library is read again in the same step: the palette
/// never shows the block gone from the broker but still listed.
class RemoveLibraryBlockAction extends Action with NonReentrant, WaitingAction {
  RemoveLibraryBlockAction(this.name);

  final String name;

  @override
  Future<AppState?> reduce() async {
    final root = site.root;
    if (root == null) {
      return null;
    }
    try {
      await invokeAll(
        deps.wyrm,
        '$root/dataflows',
        'remove_block',
        nameArgs(name),
      );
    } on WyrmException {
      // Refused: the library may still have changed (another user).
      await dispatchAndWait(RetrieveBlockLibraryAction());
      rethrow;
    }
    final read = await readLibrary(deps.wyrm, root);
    return state.copyWith.flowEditor(
      library: read.library,
      libraryOff: read.off,
    );
  }
}
