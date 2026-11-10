import 'package:models/node_detail.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../../wyrm/calls.dart';
import '../../../wyrm/failures.dart';
import '../../../wyrm/mappers/node_detail_mapper.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import 'retrieve_details_action.dart';
import 'retrieve_nodes_action.dart';
import 'set_meta_failed_action.dart';

/// Reads the full `~meta` of [key] into `nodes.detail` (the actions, `cfg`
/// and `attr` the tree's `view=list` leaves out).
///
/// The site root and its `downstream` section have no `~meta` of their own:
/// nobody answers one (the links answer for themselves below it; the root
/// times out, `downstream` answers `disconnected`). They are read as a
/// folder without a call; their children come from the tree's list.
///
/// With `quiet` (the read Studio makes when a node is selected) a failure
/// opens no dialog: it is the `read failed` mark on the node, a toast and a
/// line in Problems (docs/design/specs/errors.md §4). A form that needs the
/// meta to open (an action's parameters) keeps the dialog.
class RetrieveNodeDetailAction extends Action with WaitingAction {
  RetrieveNodeDetailAction(this.key, {super.quiet});

  @override
  Action again() => RetrieveNodeDetailAction(key, quiet: quiet);

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
    final NodeMeta m;
    try {
      m = await call(
        'meta',
        key,
        () => RetrieveDetailsAction.inTurn(() => deps.wyrm.meta(key)),
      );
    } on StudioException catch (e) {
      dispatchSync(SetMetaFailedAction(key, e.error.status?.name ?? 'failed'));
      rethrow;
    }
    return state.copyWith.nodes(
      detail: state.nodes.detail.add(key, nodeDetailOf(key, m)),
      metaFailed: state.nodes.metaFailed.remove(key),
    );
  }

  bool get _hasNoMeta {
    final root = site.root;
    return root != null && (key == root || key == '$root/downstream');
  }
}
