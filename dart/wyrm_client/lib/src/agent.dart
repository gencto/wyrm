// The calls of the agent link (`links/agent`, ADR 0005, 0049) over any
// `WyrmApi`: ask, answer, approve, read a task. The shapes they return are in
// `agent_types.dart`.

import 'dart:async';

import 'package:wyrm_core/wyrm_core.dart';

import 'agent_types.dart';
import 'api.dart';

/// The agent link's actions on [WyrmApi]. [agent] is the link's key
/// (`wy/<site>/downstream/<agent>`); a task key is
/// `…/downstream/<agent>/tasks/<id>`.
///
/// A reply that does not decode fails the call with a [WyrmException] of
/// status `invalid_message` that names the field.
extension AgentCalls on WyrmApi {
  /// `ask {task, parent?, context?}`: [AgentReply.state] (planning), then
  /// [AgentReply.event] rows, ending with [AgentReply.state]. [parent] is a
  /// task this one follows (a retry, an undo, another plan): when it waits
  /// for approval or for an answer, the new task takes its place
  /// ([AgentTaskRecord.replacedBy]). [context] are node keys the person
  /// attached.
  Stream<AgentReply> agentAsk(
    String agent,
    String task, {
    String? parent,
    List<String> context = const [],
  }) => _replies(invoke(agent, 'ask', _askArgs(task, parent, context)));

  /// The person picked [suggestion] of the task [parent] (its id): a
  /// follow-up ask with the suggestion's text and, for a suggestion with
  /// rows, the keys of the [rows] the person ticked as `context`. A parent
  /// that waited for approval or an answer is replaced by the new task.
  Stream<AgentReply> agentAskSuggestion(
    String agent,
    String parent,
    TaskSuggestion suggestion, {
    List<TaskRow> rows = const [],
  }) => agentAsk(
    agent,
    suggestion.ask(rows),
    parent: parent,
    context: [for (final r in rows) r.key],
  );

  /// `answer {answers?, text?}` on the task [key] that waits
  /// (`awaiting_answer`): [answers] by question id; [text] alone answers the
  /// whole card in words. A stream like [agentAsk]'s.
  Stream<AgentReply> agentAnswer(
    String key, {
    Map<String, AgentAnswer> answers = const {},
    String? text,
  }) => _replies(
    invoke(
      key,
      'answer',
      VMap({
        if (answers.isNotEmpty)
          'answers': VMap({
            for (final e in answers.entries) e.key: e.value.toValue(),
          }),
        'text': ?(text == null ? null : VStr(text)),
      }),
    ),
  );

  /// Approves [steps] (their numbers `n`, from 1) of the plan of the task
  /// [key]. [plan] is [planHash] of the plan the person looked at
  /// ([AgentTaskRecord.shownPlanHash]): the approval is refused when the
  /// stored plan is another one. The gateway signs each named step with the
  /// caller's rights (ADR 0049 §2) and refuses, naming the step and the
  /// right that is missing, before anything is sent; a step that is not
  /// named is skipped, with the steps that need it. Answers the task's new
  /// state, or null when the link answered nothing.
  Future<AgentReplyState?> agentApprove(
    String key, {
    required List<int> steps,
    required String plan,
  }) async {
    AgentReplyState? last;
    await for (final r in _replies(invoke(key, 'approve', _approveArgs(steps, plan)))) {
      if (r is AgentReplyState) last = r;
    }
    return last;
  }

  /// The record of the task [key] (its `~state` document). A gateway older
  /// than the `doc` op answers `invalid_parameter` ([isUnknownOp]).
  Future<AgentTaskRecord> agentRecord(String key) async =>
      decodeReply(await doc(key, DocSuffix.state.wire), AgentTaskRecord.fromValue);
}

VMap _askArgs(String task, String? parent, List<String> context) => VMap({
  'task': VStr(task),
  'parent': ?(parent == null ? null : VStr(parent)),
  if (context.isNotEmpty) 'context': VArray([for (final k in context) VStr(k)]),
});

VMap _approveArgs(List<int> steps, String plan) => VMap({
  'steps': VArray([for (final n in steps) VInt(n)]),
  'plan': VStr(plan),
});

/// Decodes each row; a row of an unknown event is skipped, a malformed one
/// ends the stream with `invalid_message`.
Stream<AgentReply> _replies(Stream<Value> rows) async* {
  await for (final v in rows) {
    final r = decodeReply(v, AgentReply.fromValue);
    if (r != null) yield r;
  }
}
