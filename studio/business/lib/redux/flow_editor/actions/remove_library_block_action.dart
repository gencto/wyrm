import 'dart:async';

import '../../../wyrm/calls.dart';
import '../../../wyrm/decode/block_library.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import 'retrieve_block_library_action.dart';

/// Deletes block [name] from the site's library (`dataflows` ▸
/// `remove_block {name}`, level config). Flows that copied it keep their
/// copies.
class RemoveLibraryBlockAction extends Action {
  RemoveLibraryBlockAction(this.name);

  final String name;

  @override
  Future<AppState?> reduce() async {
    final root = site.root;
    if (root == null) {
      return null;
    }
    await invokeAll(
      deps.wyrm,
      '$root/dataflows',
      'remove_block',
      nameArgs(name),
    );
    return null;
  }

  @override
  void after() {
    super.after();
    unawaited(dispatchAndWait(RetrieveBlockLibraryAction()));
  }
}
