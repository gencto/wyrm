// The call shapes of the agent link (`links/agent`, ADR 0005, 0049) over any
// `WyrmApi`: ask, answer, approve, and the hash an approval is bound to.

import 'package:crypto/crypto.dart';
import 'package:wyrm_core/wyrm_core.dart';

import 'api.dart';

/// The keys of a plan step in a task's `~state` that say something about the
/// step and are no part of what it does: left out of [planHash].
const planUnhashed = {'approval', 'check', 'warn', 'reason', 'result'};

/// The hash an approval is bound to (ADR 0049): SHA-256, in hex, of the
/// canonical CBOR of [plan] (the `plan` array of a task's `~state`), each step
/// without the keys of [planUnhashed]. Made from the plan as shown to the
/// person; the gateway and the agent link make it from the plan they hold and
/// refuse an approval of any other plan. Null when [plan] is not a list of
/// steps.
String? planHash(Value? plan) {
  if (plan is! VArray) return null;
  final steps = <Value>[];
  for (final s in plan.v) {
    if (s is! VMap) return null;
    steps.add(VMap({
      for (final e in s.v.entries)
        if (!planUnhashed.contains(e.key)) e.key: e.value,
    }));
  }
  return sha256.convert(VArray(steps).toCbor()).toString();
}

/// The agent link's actions on [api]. [agent] is the link's key
/// (`wy/<site>/downstream/<agent>`).
extension AgentCalls on WyrmApi {
  /// `ask {task, parent?, context?}`: a stream of `{task, state}`, then
  /// `{task, event, text}` rows (`text`, `tool`, `question`, `state`, `wait`),
  /// ending with `{task, state}`. [parent] is a task this one follows (a
  /// retry, an undo); [context] are node keys the person attached.
  Stream<Value> askAgent(String agent, String task,
          {String? parent, List<String> context = const []}) =>
      invoke(
          agent,
          'ask',
          VMap({
            'task': VStr(task),
            if (parent != null) 'parent': VStr(parent),
            if (context.isNotEmpty) 'context': VArray([for (final k in context) VStr(k)]),
          }));

  /// `answer {answers?, text?}` on the task [key] that waits
  /// (`awaiting_answer`): [answers] by question id, each the picked option ids
  /// or the person's own words; [text] alone answers the whole card in words.
  /// A stream like [askAgent]'s.
  Stream<Value> answerTask(String key, {Map<String, Object> answers = const {}, String? text}) =>
      invoke(
          key,
          'answer',
          VMap({
            if (answers.isNotEmpty)
              'answers': VMap({
                for (final e in answers.entries)
                  e.key: switch (e.value) {
                    final String s => VStr(s),
                    final Iterable<String> ids => VArray([for (final i in ids) VStr(i)]),
                    final other => throw ArgumentError.value(other, 'answers', 'option ids or text'),
                  },
              }),
            if (text != null) 'text': VStr(text),
          }));

  /// Approves [steps] (their numbers `n`, from 1) of the plan of the task
  /// [key] (`…/downstream/<agent>/tasks/<id>`). [plan] is [planHash] of the
  /// plan the person looked at: the approval is refused when the stored plan
  /// is another one. The gateway signs each named step with the caller's
  /// rights (ADR 0049 §2) and refuses, naming the step and the right that is
  /// missing, before anything is sent; a step that is not named is skipped,
  /// with the steps that need it. Answers `{task, state}`.
  Future<Value?> approveTask(String key, {required List<int> steps, required String plan}) async {
    Value? last;
    await for (final v in invoke(
        key,
        'approve',
        VMap({
          'steps': VArray([for (final n in steps) VInt(n)]),
          'plan': VStr(plan),
        }))) {
      last = v;
    }
    return last;
  }
}
