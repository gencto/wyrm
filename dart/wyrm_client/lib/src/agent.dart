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

  // ---- the old calls, rows as plain values ----

  /// `ask` with the rows as plain values.
  @Deprecated('Use agentAsk: its rows are typed (AgentReply)')
  Stream<Value> askAgent(
    String agent,
    String task, {
    String? parent,
    List<String> context = const [],
  }) => invoke(agent, 'ask', _askArgs(task, parent, context));

  /// A follow-up ask for [suggestion], rows as plain values.
  @Deprecated('Use agentAskSuggestion: its rows are typed (AgentReply)')
  Stream<Value> askSuggestion(
    String agent,
    String parent,
    TaskSuggestion suggestion, {
    List<TaskRow> rows = const [],
  }) => invoke(
    agent,
    'ask',
    _askArgs(suggestion.ask(rows), parent, [for (final r in rows) r.key]),
  );

  /// `answer` with [answers] as option ids (`Iterable<String>`) or words
  /// (`String`), rows as plain values.
  @Deprecated('Use agentAnswer: answers are AgentAnswer, rows AgentReply')
  Stream<Value> answerTask(
    String key, {
    Map<String, Object> answers = const {},
    String? text,
  }) => invoke(
    key,
    'answer',
    VMap({
      if (answers.isNotEmpty)
        'answers': VMap({
          for (final e in answers.entries)
            e.key: switch (e.value) {
              final String s => VStr(s),
              final Iterable<String> ids => VArray([
                for (final i in ids) VStr(i),
              ]),
              final other => throw ArgumentError.value(
                other,
                'answers',
                'option ids or text',
              ),
            },
        }),
      'text': ?(text == null ? null : VStr(text)),
    }),
  );

  /// `approve`, answering the last row as a plain value.
  @Deprecated('Use agentApprove: it answers AgentReplyState')
  Future<Value?> approveTask(
    String key, {
    required List<int> steps,
    required String plan,
  }) async {
    Value? last;
    await for (final v in invoke(key, 'approve', _approveArgs(steps, plan))) {
      last = v;
    }
    return last;
  }
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

// ---- the old readers of a task's record and value ----

/// The findings the agent link did not note, by why
/// (`~state.findings_refused`); empty for an older record.
@Deprecated('Use AgentTaskRecord.fromValue(record).findingsRefused')
Map<String, int> findingsRefused(Value? record) =>
    switch (record?['findings_refused']) {
      VMap(:final v) => {
        for (final e in v.entries)
          if (e.value case VInt(:final v) when v > 0) e.key: v,
      },
      _ => const {},
    };

/// How many findings the task holds, from its public `~val`.
@Deprecated('Use AgentTaskValue.fromValue(value).findings')
int findingCount(Value? value) => switch (value?['findings']) {
  VInt(:final v) => v,
  _ => 0,
};

/// The follow-up task that took the place of this one, from its record or
/// its public `~val`; null when it was not replaced.
@Deprecated('Use AgentTaskRecord.replacedBy or AgentTaskValue.replacedBy')
String? replacedBy(Value? recordOrValue) =>
    switch (recordOrValue?['replaced_by']) {
      VStr(:final v) when v.isNotEmpty => v,
      _ => null,
    };

/// How many suggestions the task holds, from its public `~val`.
@Deprecated('Use AgentTaskValue.fromValue(value).suggestions')
int suggestionCount(Value? value) => switch (value?['suggestions']) {
  VInt(:final v) => v,
  _ => 0,
};

/// Is the model reading why the run stopped?
@Deprecated('Use AgentTaskRecord.reviewing or AgentTaskValue.reviewing')
bool isReviewing(Value? recordOrValue) =>
    recordOrValue?['reviewing'] == const VBool(true);

/// What the model found after the run stopped (`~state.review`), or null.
@Deprecated('Use AgentTaskRecord.fromValue(record).review')
String? reviewOf(Value? record) => switch (record?['review']) {
  VStr(:final v) when v.isNotEmpty => v,
  _ => null,
};
