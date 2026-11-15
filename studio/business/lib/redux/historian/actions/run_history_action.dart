import '../../app_state.dart';
import '../../common/action.dart';
import '../../nodes/actions/invoke_node_action.dart';
import 'retrieve_series_action.dart';

/// An action of `sys/history` run from History ([action] of the node
/// [key], with [args]): one intent. The groups, watches and values follow
/// by themselves; the trend is read again once the broker answered (a
/// purge, a watch stopped), when points are picked.
class RunHistoryAction extends Action {
  RunHistoryAction(
    this.key,
    this.action, [
    this.args = const {},
    this.keepEmpty = const {},
  ]);

  final String key;
  final String action;
  final Map<String, Object?> args;

  /// Arguments sent even when empty (`InvokeNodeAction.keepEmpty`).
  final Set<String> keepEmpty;

  @override
  Future<AppState?> reduce() async {
    final ran = await dispatchAndWait(
      InvokeNodeAction(key, action, args, keepEmpty),
    );
    if (ran.isCompletedOk && historian.points.isNotEmpty) {
      await dispatchAndWait(RetrieveSeriesAction());
    }
    return null;
  }
}
