// The call shapes of the agent link (`links/agent`, ADR 0005, 0049) over any
// `WyrmApi`: ask, answer, approve, and the hash an approval is bound to.

import 'package:crypto/crypto.dart';
import 'package:wyrm_core/wyrm_core.dart';

import 'api.dart';

/// The keys of a plan step in a task's `~state` that say something about the
/// step and are no part of what it does: left out of [planHash].
/// `warn` is the link's own finding, `model_warn` the model's words.
const planUnhashed = {'approval', 'check', 'warn', 'model_warn', 'reason', 'result'};

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

String _text(Value? v) => v is VStr ? v.v : '';

/// One row of a [TaskSuggestion]: a node the same thing may be done for.
class TaskRow {
  /// The full node key; what goes into `ask {context}`.
  final String key;
  final String label;
  final String detail;
  const TaskRow({required this.key, required this.label, this.detail = ''});
}

/// What the model offers the person to ask next (`~state.suggestions`, ADR
/// 0049 amendment of 2026-11-14): a fix for a step's warning ([step] set),
/// the same change for more nodes ([rows]), or a way out of a run that
/// stopped. It is text of the model: data for a card, never a command.
/// Picking it sends a follow-up ask ([AgentCalls.askSuggestion]); what that
/// changes is a new plan the person approves.
class TaskSuggestion {
  final String id;
  final String label;
  final String detail;

  /// How many changes the model expects the follow-up to plan; 0: nothing
  /// changes. The model's guess, for the tag on the card.
  final int changes;

  /// The plan step (`n`, from 1) this is a fix for; null: about the task.
  final int? step;
  final List<TaskRow> rows;
  const TaskSuggestion(
      {required this.id,
      required this.label,
      this.detail = '',
      this.changes = 0,
      this.step,
      this.rows = const []});

  /// The suggestions of a task's `~state` [record]; empty for a record of an
  /// agent link older than the field.
  static List<TaskSuggestion> of(Value? record) {
    final list = record?['suggestions'];
    if (list is! VArray) return const [];
    return [
      for (final s in list.v)
        if (s is VMap)
          TaskSuggestion(
            id: _text(s['id']),
            label: _text(s['label']),
            detail: _text(s['detail']),
            changes: switch (s['changes']) { VInt(:final v) => v, _ => 0 },
            step: switch (s['step']) { VInt(:final v) => v, _ => null },
            rows: [
              if (s['rows'] case VArray(:final v))
                for (final r in v)
                  if (r is VMap)
                    TaskRow(key: _text(r['key']), label: _text(r['label']), detail: _text(r['detail'])),
            ],
          ),
    ];
  }

  /// The text of the follow-up ask: what the person saw on the card, and
  /// the labels of the [picked] rows.
  String ask([Iterable<TaskRow> picked = const []]) {
    final b = StringBuffer(label);
    if (detail.isNotEmpty) b.write('. $detail');
    if (picked.isNotEmpty) b.write('\nFor: ${picked.map((r) => r.label).join(', ')}');
    return b.toString();
  }
}

/// The follow-up task that took the place of a task that waited for a person
/// (`replaced_by` in its `~state` record and in its public `~val`); null
/// when the task was not replaced. The plan of a replaced task is shown as
/// replaced and cannot be approved.
String? replacedBy(Value? recordOrValue) => switch (recordOrValue?['replaced_by']) {
      VStr(:final v) when v.isNotEmpty => v,
      _ => null,
    };

/// How many suggestions the task holds, from its public `~val` (the texts
/// are in the record, read with `doc`).
int suggestionCount(Value? value) => switch (value?['suggestions']) { VInt(:final v) => v, _ => 0 };

/// Is the model reading why the run stopped (`reviewing` in `~val` and
/// `~state`)? Its ways out come as suggestions when it ends.
bool isReviewing(Value? recordOrValue) => recordOrValue?['reviewing'] == const VBool(true);

/// What the model found after the run stopped (`~state.review`), or null.
String? reviewOf(Value? record) => switch (record?['review']) {
      VStr(:final v) when v.isNotEmpty => v,
      _ => null,
    };

/// The agent link's actions on [api]. [agent] is the link's key
/// (`wy/<site>/downstream/<agent>`).
extension AgentCalls on WyrmApi {
  /// `ask {task, parent?, context?}`: a stream of `{task, state}`, then
  /// `{task, event, text}` rows (`text`, `tool`, `question`, `state`, `wait`),
  /// ending with `{task, state}`. [parent] is a task this one follows (a
  /// retry, an undo, another plan): when it waits for approval or for an
  /// answer, the new task takes its place ([replacedBy]). [context] are
  /// node keys the person attached.
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

  /// The person picked [suggestion] of the task [parent] (its id): a
  /// follow-up ask with the suggestion's text and, for a suggestion with
  /// rows, the keys of the [rows] the person ticked as `context`. A parent
  /// that waited for approval or an answer is replaced by the new task.
  Stream<Value> askSuggestion(String agent, String parent, TaskSuggestion suggestion,
          {List<TaskRow> rows = const []}) =>
      askAgent(agent, suggestion.ask(rows), parent: parent, context: [for (final r in rows) r.key]);

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
