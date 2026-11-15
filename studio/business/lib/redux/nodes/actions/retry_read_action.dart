import '../../app_state.dart';
import '../../common/action.dart';
import 'retrieve_node_detail_action.dart';

/// *Try again* on a `read failed` mark (docs/design/specs/errors.md §4):
/// every read of [key] that failed is made again — its list is opened, its
/// value subscribed, its `~meta` read (this action ends when it answers).
/// A mark goes when its read answers; one that fails again stays, and is
/// one line in Problems as before.
class RetryReadAction extends Action {
  RetryReadAction(this.key);

  final String key;

  @override
  Future<AppState?> reduce() async {
    if (nodes.listFailed.containsKey(key)) {
      deps.treeWatch.open(key);
    }
    if (live.failed.containsKey(key)) {
      deps.liveValues.retry(key);
    }
    if (nodes.metaFailed.containsKey(key)) {
      await dispatchAndWait(RetrieveNodeDetailAction(key, quiet: true));
    }
    return null;
  }
}
