// The typed shapes of the agent link (`links/agent`, ADR 0005, ADR 0049): a
// task's public `~val`, its restricted `~state` record, the rows of the
// `ask`/`answer` streams, and the closed sets in them. Each shape has one
// decoder, `fromValue`, that throws a `DecodeError` naming the field.
//
// The sources of truth, checked by `test/wire_sources_test.dart`:
// `links/agent/src/lib.rs` (the `TaskState` wire_enum, the stream events,
// the record layout in its module doc) and `links/agent/src/tools.rs`
// (`StepStatus`, `Check`, `Refused`, the step run format).

import 'package:crypto/crypto.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:wyrm_core/wyrm_core.dart';

part 'agent_types.freezed.dart';

/// The state of a task (`tasks/<id>` `~val.state`, by name; `lib.rs`
/// `wire_enum! TaskState`). Closed.
enum AgentTaskState implements WireCode {
  planning(0, 'planning'),
  awaitingApproval(1, 'awaiting_approval'),
  running(2, 'running'),
  done(3, 'done'),
  failed(4, 'failed'),

  /// The model asked the person; `answer` resumes it (ADR 0049 §5).
  awaitingAnswer(5, 'awaiting_answer');

  @override
  final int code;
  @override
  final String wire;
  const AgentTaskState(this.code, this.wire);

  /// `done` or `failed`: nothing more happens to the task.
  bool get finished => this == done || this == failed;

  static AgentTaskState? fromCode(int c) => wireByCode(values, c);
  static AgentTaskState? fromWire(String s) => wireByName(values, s);
}

/// How a step ended (`tools.rs` `StepStatus`). Closed.
enum AgentStepStatus implements WireName {
  ok('ok'),
  failed('failed'),

  /// Left out by the approver, or a step that needs one left out.
  skipped('skipped');

  @override
  final String wire;
  const AgentStepStatus(this.wire);

  static AgentStepStatus? fromWire(String s) => wireByName(values, s);
}

/// When a step was checked against the tree (`tools.rs` `Check`). Closed;
/// absent reads as [now].
enum AgentStepCheck implements WireName {
  /// Checked against the live tree when it was proposed.
  now('now'),

  /// Its node does not exist yet (an earlier step makes it): checked when
  /// it runs.
  atRun('at_run');

  @override
  final String wire;
  const AgentStepCheck(this.wire);

  static AgentStepCheck? fromWire(String s) => wireByName(values, s);
}

/// What a plan step does: the key of the `wyrm-agent run` format it has
/// (`tools.rs` `run_format`).
enum AgentStepKind implements WireName {
  set('set'),
  invoke('invoke'),
  wait('wait'),
  expect('expect'),
  sleep('sleep_s');

  @override
  final String wire;
  const AgentStepKind(this.wire);
}

/// Why a finding of the model was not noted (`~state.findings_refused`;
/// `tools.rs` `Refused`). Fixed words of the link; the set may grow, so a
/// reason this client does not know is left out of
/// [AgentTaskRecord.findingsRefused].
enum AgentFindingRefusal implements WireName {
  rightsUnknown('rights_unknown'),
  rightsExpired('rights_expired'),
  outsideRights('outside_rights'),
  limit('limit'),
  invalid('invalid');

  @override
  final String wire;
  const AgentFindingRefusal(this.wire);

  static AgentFindingRefusal? fromWire(String s) => wireByName(values, s);
}

/// The `event` of a progress row on the `ask`/`answer` stream (`lib.rs`
/// `progress`). The set may grow: a row with an event this client does not
/// know is skipped ([AgentReply.fromValue] returns null).
enum AgentEventKind implements WireName {
  /// A line of the model's text.
  text('text'),

  /// A read-only tool the model called (`<name>` or `<name> (error)`).
  tool('tool'),

  /// A question to the person (`ask_user`).
  question('question'),

  /// The task's state changed (the text is the state's name).
  state('state'),

  /// Still waiting for the model (a tick).
  wait('wait');

  @override
  final String wire;
  const AgentEventKind(this.wire);

  static AgentEventKind? fromWire(String s) => wireByName(values, s);
}

/// The keys of a plan step in a task's `~state` that say something about the
/// step and are no part of what it does: left out of [planHash] (`tools.rs`
/// `UNHASHED`). `warn` is the link's own finding, `model_warn` the model's
/// words.
const planUnhashed = {
  'approval',
  'check',
  'warn',
  'model_warn',
  'reason',
  'result',
};

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
    steps.add(
      VMap({
        for (final e in s.v.entries)
          if (!planUnhashed.contains(e.key)) e.key: e.value,
      }),
    );
  }
  return sha256.convert(VArray(steps).toCbor()).toString();
}

/// One row of a [TaskSuggestion]: a node the same thing may be done for.
@freezed
abstract class TaskRow with _$TaskRow {
  const TaskRow._();

  const factory TaskRow({
    /// The full node key; what goes into `ask {context}`.
    required String key,
    required String label,
    @Default('') String detail,
  }) = _TaskRow;

  /// `key` is required; `label` and `detail` may be absent (empty).
  factory TaskRow.fromValue(Value v, [String path = 'TaskRow']) {
    final m = WireMap.of(v, path);
    return TaskRow(
      key: m.str('key'),
      label: m.strOr('label', ''),
      detail: m.strOr('detail', ''),
    );
  }
}

/// What the model offers the person to ask next (`~state.suggestions`, ADR
/// 0049 amendment of 2026-11-14): a fix for a step's warning ([step] set),
/// the same change for more nodes ([rows]), or a way out of a run that
/// stopped. It is text of the model: data for a card, never a command.
/// Picking it sends a follow-up ask ([AgentCalls.agentAskSuggestion]); what
/// that changes is a new plan the person approves.
@freezed
abstract class TaskSuggestion with _$TaskSuggestion {
  const TaskSuggestion._();

  const factory TaskSuggestion({
    required String id,
    required String label,
    @Default('') String detail,

    /// How many changes the model expects the follow-up to plan; 0: nothing
    /// changes. The model's guess, for the tag on the card.
    @Default(0) int changes,

    /// The plan step (`n`, from 1) this is a fix for; null: about the task.
    int? step,
    @Default(<TaskRow>[]) List<TaskRow> rows,
  }) = _TaskSuggestion;

  /// `id` and `label` are required.
  factory TaskSuggestion.fromValue(Value v, [String path = 'TaskSuggestion']) {
    final m = WireMap.of(v, path);
    return TaskSuggestion(
      id: m.str('id'),
      label: m.str('label'),
      detail: m.strOr('detail', ''),
      changes: m.integerOr('changes', 0),
      step: m.integerOrNull('step'),
      rows: m.listOr('rows', TaskRow.fromValue),
    );
  }

  /// The text of the follow-up ask: what the person saw on the card, and
  /// the labels of the [picked] rows.
  String ask([Iterable<TaskRow> picked = const []]) {
    final b = StringBuffer(label);
    if (detail.isNotEmpty) b.write('. $detail');
    if (picked.isNotEmpty) {
      b.write('\nFor: ${picked.map((r) => r.label).join(', ')}');
    }
    return b.toString();
  }
}

/// What the model read about one node (`~state.findings`, ADR 0049
/// amendment 2 of 2026-11-14): a row of *What I found*. [label] and [detail]
/// are the model's words, shown as plain text; [key] is a node the agent link
/// checked the task's asker may read. A mark good or bad is never the
/// model's: a client takes it from the node's live value, read with its own
/// rights.
@freezed
abstract class TaskFinding with _$TaskFinding {
  const TaskFinding._();

  const factory TaskFinding({
    /// The full node key.
    required String key,
    required String label,
    @Default('') String detail,
  }) = _TaskFinding;

  /// `key` is required (and not empty: the link drops such findings).
  factory TaskFinding.fromValue(Value v, [String path = 'TaskFinding']) {
    final m = WireMap.of(v, path);
    final key = m.str('key');
    if (key.isEmpty) throw DecodeError('$path.key', 'a node key', 'empty text');
    return TaskFinding(
      key: key,
      label: m.strOr('label', ''),
      detail: m.strOr('detail', ''),
    );
  }
}

/// One option of an [AgentQuestion].
@freezed
abstract class AgentChoice with _$AgentChoice {
  const factory AgentChoice({
    required String id,
    required String label,
    @Default('') String detail,
  }) = _AgentChoice;

  factory AgentChoice.fromValue(Value v, [String path = 'AgentChoice']) {
    final m = WireMap.of(v, path);
    return AgentChoice(
      id: m.str('id'),
      label: m.strOr('label', ''),
      detail: m.strOr('detail', ''),
    );
  }
}

/// What the model asked the person (`ask_user`, `~state.questions`).
@freezed
abstract class AgentQuestion with _$AgentQuestion {
  const factory AgentQuestion({
    /// `q1`, `q2`, …: unique in the task.
    required String id,
    required String text,
    @Default(<AgentChoice>[]) List<AgentChoice> options,

    /// More than one option may be picked.
    @Default(false) bool multiple,

    /// The person may answer in their own words.
    @Default(false) bool freeText,

    /// The answer given: the picked option ids or the person's words.
    AgentAnswer? answer,
  }) = _AgentQuestion;

  factory AgentQuestion.fromValue(Value v, [String path = 'AgentQuestion']) {
    final m = WireMap.of(v, path);
    return AgentQuestion(
      id: m.str('id'),
      text: m.strOr('text', ''),
      options: m.listOr('options', AgentChoice.fromValue),
      multiple: m.booleanOr('multiple', false),
      freeText: m.booleanOr('free_text', false),
      answer: m.has('answer')
          ? AgentAnswer.fromValue(m['answer'], '$path.answer')
          : null,
    );
  }
}

/// An answer to one [AgentQuestion]: the picked option ids or the person's
/// own words (`answer {answers}`).
@freezed
sealed class AgentAnswer with _$AgentAnswer {
  const AgentAnswer._();

  const factory AgentAnswer.options(List<String> ids) = AgentAnswerOptions;
  const factory AgentAnswer.text(String text) = AgentAnswerText;

  /// An array of option ids, or text.
  factory AgentAnswer.fromValue(Value? v, [String path = 'AgentAnswer']) =>
      switch (v) {
        VStr(:final v) => AgentAnswer.text(v),
        VArray(:final v) => AgentAnswer.options([
          for (final (i, s) in v.indexed)
            switch (s) {
              VStr(:final v) => v,
              _ => throw DecodeError.of('$path[$i]', 'an option id', s),
            },
        ]),
        _ => throw DecodeError.of(path, 'option ids or text', v),
      };

  Value toValue() => switch (this) {
    AgentAnswerOptions(:final ids) => VArray([for (final i in ids) VStr(i)]),
    AgentAnswerText(:final text) => VStr(text),
  };
}

/// How a step ended (`result` of a plan step).
@freezed
abstract class AgentStepResult with _$AgentStepResult {
  const factory AgentStepResult({
    required AgentStepStatus status,

    /// The responder's answer in short, its refusal, or why it was skipped.
    @Default('') String message,

    /// When the step ended, seconds since the Unix epoch (0: not told).
    @Default(0) int time,
  }) = _AgentStepResult;

  factory AgentStepResult.fromValue(
    Value v, [
    String path = 'AgentStepResult',
  ]) {
    final m = WireMap.of(v, path);
    return AgentStepResult(
      status: m.name('status', AgentStepStatus.values),
      message: m.strOr('message', ''),
      time: m.integerOr('time', 0),
    );
  }
}

/// One step of a task's plan, as `~state.plan` shows it: the `wyrm-agent
/// run` step (`{set, value}`, `{invoke, action, args}`, `{wait, timeout_s}`,
/// `{expect, equals | min/max | changes, timeout_s}`, `{sleep_s}`) with what
/// the link says about it.
@freezed
abstract class AgentPlanStep with _$AgentPlanStep {
  const factory AgentPlanStep({
    /// The step's number, from 1.
    required int n,
    required AgentStepKind kind,

    /// The full node key; null for [AgentStepKind.sleep].
    String? node,

    /// `set`: the value to write.
    Value? value,

    /// `invoke`: the action and its arguments.
    String? action,
    Value? args,

    /// `wait`/`expect`: how long to wait; `sleep`: how long to sleep (s).
    double? seconds,

    /// `expect`: the value to see, or the range, or any change.
    Value? equals,
    double? min,
    double? max,
    @Default(false) bool changes,

    /// The level the step needs.
    required Perm level,

    /// The steps (`n`) this one runs after.
    @Default(<int>[]) List<int> after,

    /// It needs a person's approval (the bar of now).
    @Default(false) bool approval,
    @Default(AgentStepCheck.now) AgentStepCheck check,

    /// The link's own finding about the step.
    String? warn,

    /// The model's words about a risk.
    String? modelWarn,
    String? reason,
    AgentStepResult? result,
  }) = _AgentPlanStep;

  factory AgentPlanStep.fromValue(Value v, [String path = 'AgentPlanStep']) {
    final m = WireMap.of(v, path);
    final kind = switch (m) {
      _ when m.has('set') => AgentStepKind.set,
      _ when m.has('invoke') => AgentStepKind.invoke,
      _ when m.has('wait') => AgentStepKind.wait,
      _ when m.has('expect') => AgentStepKind.expect,
      _ when m.has('sleep_s') => AgentStepKind.sleep,
      _ => throw DecodeError(
        path,
        'one of set, invoke, wait, expect, sleep_s',
        'none of them',
      ),
    };
    return AgentPlanStep(
      n: m.integer('n'),
      kind: kind,
      node: kind == AgentStepKind.sleep ? null : m.str(kind.wire),
      value: kind == AgentStepKind.set ? m['value'] ?? const VNull() : null,
      action: kind == AgentStepKind.invoke ? m.str('action') : null,
      args: kind == AgentStepKind.invoke ? m['args'] ?? const VMap({}) : null,
      seconds: switch (kind) {
        AgentStepKind.sleep => m.number('sleep_s'),
        AgentStepKind.wait || AgentStepKind.expect => m.numberOrNull(
          'timeout_s',
        ),
        AgentStepKind.set || AgentStepKind.invoke => null,
      },
      equals: kind == AgentStepKind.expect ? m['equals'] : null,
      min: kind == AgentStepKind.expect ? m.numberOrNull('min') : null,
      max: kind == AgentStepKind.expect ? m.numberOrNull('max') : null,
      changes: kind == AgentStepKind.expect && m.booleanOr('changes', false),
      level: m.perm('level'),
      after: m.integersOr('after'),
      approval: m.booleanOr('approval', false),
      check: m.nameOr('check', AgentStepCheck.values, AgentStepCheck.now),
      warn: m.strOrNull('warn'),
      modelWarn: m.strOrNull('model_warn'),
      reason: m.strOrNull('reason'),
      result: m.has('result')
          ? AgentStepResult.fromValue(m['result']!, '$path.result')
          : null,
    );
  }
}

/// The latest finished step in a task's public `~val`.
@freezed
abstract class AgentLastStep with _$AgentLastStep {
  const factory AgentLastStep({
    required int n,
    required bool ok,
    required AgentStepStatus result,
  }) = _AgentLastStep;

  factory AgentLastStep.fromValue(Value v, [String path = 'AgentLastStep']) {
    final m = WireMap.of(v, path);
    return AgentLastStep(
      n: m.integer('n'),
      ok: m.boolean('ok'),
      result: m.name('result', AgentStepStatus.values),
    );
  }
}

/// A task's public `~val`: `{state, step, of, last?, suggestions?,
/// findings?, reviewing?, replaced_by?}` (numbers, fixed words and task ids
/// only; the texts are in the record, [AgentTaskRecord]).
@freezed
abstract class AgentTaskValue with _$AgentTaskValue {
  const factory AgentTaskValue({
    required AgentTaskState state,

    /// Steps run so far, of [of].
    required int step,
    required int of,
    AgentLastStep? last,

    /// How many suggestions and findings the record holds.
    @Default(0) int suggestions,
    @Default(0) int findings,

    /// The model reads why the run stopped.
    @Default(false) bool reviewing,

    /// The follow-up task that took this one's place.
    String? replacedBy,
  }) = _AgentTaskValue;

  /// `state`, `step` and `of` are required (`lib.rs` module doc); the
  /// others are optional.
  factory AgentTaskValue.fromValue(Value v) {
    final m = WireMap.of(v, 'AgentTaskValue');
    return AgentTaskValue(
      state: m.name('state', AgentTaskState.values),
      step: m.integer('step'),
      of: m.integer('of'),
      last: m.has('last')
          ? AgentLastStep.fromValue(m['last']!, 'AgentTaskValue.last')
          : null,
      suggestions: m.integerOr('suggestions', 0),
      findings: m.integerOr('findings', 0),
      reviewing: m.booleanOr('reviewing', false),
      replacedBy: m.textOrNull('replaced_by'),
    );
  }
}

/// A task's restricted record, the `~state` document of `tasks/<id>`:
/// `{state, owner, ask, plan[], plan_hash, questions[]?, suggestions[]?,
/// findings[]?, findings_refused?, parent?, replaced_by?, context[]?, step,
/// log[], error?, review?, reviewing?, tokens}`.
@freezed
abstract class AgentTaskRecord with _$AgentTaskRecord {
  const factory AgentTaskRecord({
    required AgentTaskState state,

    /// The subject who asked.
    required String owner,

    /// What the person asked.
    required String ask,
    required List<AgentPlanStep> plan,

    /// The hash of the plan the link holds (`plan_hash`).
    required String planHash,

    /// [planHash] of the plan in this record, made here: what an approval
    /// of the plan as shown sends (`approve {plan}`).
    required String shownPlanHash,
    @Default(<AgentQuestion>[]) List<AgentQuestion> questions,
    @Default(<TaskSuggestion>[]) List<TaskSuggestion> suggestions,
    @Default(<TaskFinding>[]) List<TaskFinding> findings,

    /// The findings not noted, by why (reasons this client does not know
    /// are left out).
    @Default(<AgentFindingRefusal, int>{})
    Map<AgentFindingRefusal, int> findingsRefused,

    /// The task this one follows (a retry, an undo, another plan).
    String? parent,

    /// The follow-up task that took this one's place: its plan is shown as
    /// replaced and cannot be approved.
    String? replacedBy,

    /// Node keys the person attached.
    @Default(<String>[]) List<String> context,

    /// Steps run so far.
    required int step,
    required List<String> log,
    String? error,

    /// What the model found after the run stopped.
    String? review,

    /// The model reads why the run stopped; its ways out come as
    /// suggestions when it ends.
    @Default(false) bool reviewing,

    /// LLM tokens the task used.
    required int tokens,
  }) = _AgentTaskRecord;

  /// `state`, `owner`, `ask`, `plan`, `plan_hash`, `step`, `log` and
  /// `tokens` are required (`lib.rs` module doc); the fields marked `?`
  /// there are optional.
  factory AgentTaskRecord.fromValue(Value v) {
    final m = WireMap.of(v, 'AgentTaskRecord');
    return AgentTaskRecord(
      state: m.name('state', AgentTaskState.values),
      owner: m.str('owner'),
      ask: m.str('ask'),
      plan: m.list('plan', AgentPlanStep.fromValue),
      planHash: m.str('plan_hash'),
      // never null: every step decoded as a map
      shownPlanHash: planHash(m['plan'])!,
      questions: m.listOr('questions', AgentQuestion.fromValue),
      suggestions: m.listOr('suggestions', TaskSuggestion.fromValue),
      findings: m.listOr('findings', TaskFinding.fromValue),
      findingsRefused: {
        if (m.mapOrNull('findings_refused') case final r?)
          for (final e in r.fields.keys)
            if (AgentFindingRefusal.fromWire(e) case final why?)
              if (r.integer(e) case final n when n > 0) why: n,
      },
      parent: m.textOrNull('parent'),
      replacedBy: m.textOrNull('replaced_by'),
      context: m.stringsOr('context'),
      step: m.integer('step'),
      log: m.strings('log'),
      error: m.strOrNull('error'),
      review: m.textOrNull('review'),
      reviewing: m.booleanOr('reviewing', false),
      tokens: m.integer('tokens'),
    );
  }
}

/// A row of the `ask` and `answer` streams, and the answer of `approve`.
@freezed
sealed class AgentReply with _$AgentReply {
  const AgentReply._();

  /// `{task, state}`: the first and the last row, and `approve`'s answer.
  const factory AgentReply.state({
    required String task,
    required AgentTaskState state,
  }) = AgentReplyState;

  /// `{task, event, text}`: progress.
  const factory AgentReply.event({
    required String task,
    required AgentEventKind kind,
    required String text,
  }) = AgentReplyEvent;

  /// The task id of the row.
  String get taskId => switch (this) {
    AgentReplyState(:final task) => task,
    AgentReplyEvent(:final task) => task,
  };

  /// The row [v]; null for a progress row of an event this client does not
  /// know ([AgentEventKind]).
  static AgentReply? fromValue(Value v) {
    final m = WireMap.of(v, 'AgentReply');
    final task = m.str('task');
    if (m.has('event')) {
      final kind = AgentEventKind.fromWire(m.str('event'));
      if (kind == null) return null;
      return AgentReply.event(task: task, kind: kind, text: m.strOr('text', ''));
    }
    return AgentReply.state(
      task: task,
      state: m.name('state', AgentTaskState.values),
    );
  }
}
