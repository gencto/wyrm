import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/block_info.dart';
import 'package:models/library_off.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../../wyrm/decode/block_library.dart';
import '../../app_state.dart';
import '../../common/action.dart';

/// Reads the site's library of custom blocks (`dataflows` ▸ `list_blocks`,
/// ADR 0040 §3) into `flowEditor.library`. A broker that does not answer it
/// has no custom blocks: `flowEditor.libraryOff` keeps why, and the editor
/// shows them off with that reason. Never a dialog: the editor asks by
/// itself.
class RetrieveBlockLibraryAction extends Action {
  @override
  Future<AppState?> reduce() async {
    final root = site.root;
    if (root == null) {
      return null;
    }
    final read = await readLibrary(deps.wyrm, root);
    return state.copyWith.flowEditor(
      library: read.library,
      libraryOff: read.off,
    );
  }
}

/// The library of the site at [root] (`list_blocks`), or why it is off.
Future<({IList<BlockInfo> library, LibraryOff? off})> readLibrary(
  WyrmApi api,
  String root,
) async {
  try {
    final rows = await api.invoke('$root/dataflows', 'list_blocks').toList();
    return (
      library: blockListOf(rows, where: 'list_blocks of $root').lock,
      off: null,
    );
  } on WyrmException catch (e) {
    return (
      library: const IListConst<BlockInfo>([]),
      off: LibraryOff.refused(e.status),
    );
  }
}
