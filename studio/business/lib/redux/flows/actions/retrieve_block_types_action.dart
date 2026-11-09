import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/node_type.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../../wyrm/calls.dart';
import '../../../wyrm/mappers/flow_mapper.dart';
import '../../app_state.dart';
import '../../common/action.dart';

/// Reads the flow block catalogue of the site (`dataflows` ▸ `node_types`)
/// into `flows.blockTypes`, the cache the flow editor opens from. Read once
/// per session and per site (the log-in preload, docs/design/specs/login.md
/// §5); a site switch clears it.
class RetrieveBlockTypesAction extends Action with WaitingAction {
  RetrieveBlockTypesAction({super.quiet});

  @override
  Future<AppState?> reduce() async {
    final root = site.root;
    if (root == null) {
      return null;
    }
    final types = await readBlockTypes(deps.wyrm, root);
    return state.copyWith.flows(blockTypes: types);
  }
}

/// The block catalogue of the site at [root], sorted by category, then type.
Future<IList<NodeType>> readBlockTypes(WyrmApi api, String root) async {
  final cat = await invokeOne(api, '$root/dataflows', 'node_types');
  final types =
      [
        if (cat case VArray(:final v))
          for (final t in v) nodeTypeOf(t),
      ]..sort(
        (a, b) => a.category == b.category
            ? a.type.compareTo(b.type)
            : a.category.compareTo(b.category),
      );
  return types.lock;
}
