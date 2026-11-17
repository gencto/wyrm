import 'package:wyrm_client/wyrm_client.dart';

import '../../../wyrm/calls.dart';
import '../../../wyrm/decode/action_answer.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import 'retrieve_node_detail_action.dart';

/// Runs [action] on [key] with [args] now (not staged: an action that does
/// something, not an edit) and keeps its answer, a table or JSON lines, in
/// `nodes.answers['<key> ▸ <action>']`.
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
  Future<AppState> reduce() => run(this, key, action, args, keepEmpty);

  /// [action] run on [key] by [by], and the state with its answer kept: the
  /// one body of every action that runs a node's action now (this one, the
  /// inspector's form), so a refusal is the running action's own error.
  static Future<AppState> run(
    Action by,
    String key,
    String action,
    Map<String, Object?> args,
    Set<String> keepEmpty,
  ) async {
    final rows = await invokeAll(
      by.deps.wyrm,
      key,
      action,
      args.isEmpty ? null : Value.from(argsToSend(args, keepEmpty: keepEmpty)),
    );
    for (final r in rows) {
      requireSuccess(r, key, action);
    }
    final s = by.state;
    return s.copyWith.nodes(
      answers: s.nodes.answers.add(resultId(key, action), actionAnswerOf(rows)),
    );
  }
}
