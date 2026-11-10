import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../../wyrm/mappers/flow_blocks.dart';
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
    try {
      final rows = await deps.wyrm
          .invoke('$root/dataflows', 'list_blocks')
          .toList();
      final list = switch (rows) {
        [VArray(:final v)] => v,
        _ => rows,
      };
      final blocks = [for (final r in list) blockInfoOf(r)]
        ..removeWhere((b) => b.name.isEmpty)
        ..sort((a, b) => a.name.compareTo(b.name));
      return state.copyWith.flowEditor(library: blocks.lock, libraryOff: null);
    } on WyrmException catch (e) {
      return state.copyWith.flowEditor(
        library: const IListConst([]),
        libraryOff: e.status.name,
      );
    }
  }
}
