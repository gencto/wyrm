import 'dart:async';

import '../../app_state.dart';
import '../../common/action.dart';
import 'retrieve_node_detail_action.dart';

/// *Try again* on a `read failed` mark (docs/design/specs/errors.md §4):
/// every read of [key] that failed is made again — its list is opened, its
/// `~meta` read, its value subscribed. A mark goes when its read answers;
/// one that fails again stays, and is one line in Problems as before.
class RetryReadAction extends Action {
  RetryReadAction(this.key);

  final String key;

  @override
  AppState? reduce() {
    if (nodes.listFailed.containsKey(key)) {
      deps.treeWatch.open(key);
    }
    if (nodes.metaFailed.containsKey(key)) {
      unawaited(
        dispatchAndWait(RetrieveNodeDetailAction(key, quiet: true)),
      );
    }
    if (live.failed.containsKey(key)) {
      deps.liveValues.retry(key);
    }
    return null;
  }
}
