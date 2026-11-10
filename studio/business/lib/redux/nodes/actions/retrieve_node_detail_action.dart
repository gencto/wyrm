import 'package:models/node_detail.dart';

import '../../../wyrm/calls.dart';
import '../../../wyrm/mappers/node_detail_mapper.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import 'retrieve_details_action.dart';
import 'retrieve_nodes_action.dart';

/// Reads the full `~meta` of [key] into `nodes.detail` (the actions, `cfg`
/// and `attr` the tree's `view=list` leaves out).
///
/// The site root and its `downstream` section have no `~meta` of their own:
/// nobody answers one (the links answer for themselves below it; the root
/// times out, `downstream` answers `disconnected`). They are read as a
/// folder without a call; their children come from the tree's list.
class RetrieveNodeDetailAction extends Action with WaitingAction {
  RetrieveNodeDetailAction(this.key);

  @override
  Action again() => RetrieveNodeDetailAction(key);

  @override
  Action reload() => RetrieveNodesAction();

  final String key;

  @override
  Future<AppState> reduce() async {
    if (_hasNoMeta) {
      return state.copyWith.nodes(
        detail: state.nodes.detail.add(
          key,
          NodeDetail(key: key, profile: 'wy:folder'),
        ),
      );
    }
    final m = await call(
      'meta',
      key,
      () => RetrieveDetailsAction.inTurn(() => deps.wyrm.meta(key)),
    );
    return state.copyWith.nodes(
      detail: state.nodes.detail.add(key, nodeDetailOf(key, m)),
    );
  }

  bool get _hasNoMeta {
    final root = site.root;
    return root != null && (key == root || key == '$root/downstream');
  }
}
