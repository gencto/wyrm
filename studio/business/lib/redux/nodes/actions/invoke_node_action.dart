import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../../wyrm/calls.dart';
import '../../../wyrm/mappers/values.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import '../../links/actions/retrieve_link_history_action.dart';
import 'retrieve_node_detail_action.dart';

/// Runs [action] on [key] with [args] now (not staged: an action that does
/// something, not an edit) and keeps its answer rows, as indented JSON, in
/// `nodes.results['<key> ▸ <action>']`.
///
/// A refusal is a user error with the broker's own message; an answer
/// `{success: false, message}` is one too.
class InvokeNodeAction extends Action with WaitingAction {
  InvokeNodeAction(
    this.key,
    this.action, [
    this.args = const {},
    this.keepEmpty = const {},
  ]);

  @override
  Action again() => InvokeNodeAction(key, action, args, keepEmpty);

  @override
  Action reload() => RetrieveNodeDetailAction(key);

  final String key;
  final String action;
  final Map<String, Object?> args;

  /// Arguments sent even when empty ([argsToSend], [clearedNames]).
  final Set<String> keepEmpty;

  /// Where the answer of [key] ▸ [action] is kept.
  static String resultId(String key, String action) => '$key ▸ $action';

  @override
  Future<AppState> reduce() async {
    final rows = await invokeAll(
      deps.wyrm,
      key,
      action,
      args.isEmpty ? null : Value.from(argsToSend(args, keepEmpty: keepEmpty)),
    );
    for (final r in rows) {
      requireSuccess(r, key, action);
    }
    return state.copyWith.nodes(
      results: state.nodes.results.add(
        resultId(key, action),
        [for (final r in rows) prettyJson(toDart(r))].lock,
      ),
    );
  }
}
