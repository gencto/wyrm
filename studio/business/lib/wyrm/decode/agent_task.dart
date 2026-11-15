import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/agent_task.dart';
import 'package:models/finding_refusal.dart';
import 'package:models/plan_step.dart';
import 'package:models/step_check.dart';
import 'package:models/step_kind.dart';
import 'package:models/step_result.dart';
import 'package:models/step_status.dart';
import 'package:models/task_event.dart';
import 'package:models/task_event_kind.dart';
import 'package:models/task_finding.dart';
import 'package:models/task_option.dart';
import 'package:models/task_question.dart';
import 'package:models/task_row.dart';
import 'package:models/task_state.dart';
import 'package:models/task_suggestion.dart';
import 'package:wyrm_client/wyrm_client.dart'
    show
        AgentAnswerOptions,
        AgentAnswerText,
        AgentFindingRefusal,
        AgentPlanStep,
        AgentQuestion,
        AgentStepCheck,
        AgentStepKind,
        AgentStepResult,
        AgentStepStatus,
        AgentTaskRecord,
        AgentTaskState,
        AgentTaskValue,
        DecodeError,
        Value;

import '../mappers/values.dart' show toDart;
import 'decoded.dart';

// The agent link's task (`links/agent`, ADR 0049) as Studio's domain: the
// `~state` record and the public `~val` are decoded by `wyrm_client`
// (`AgentTaskRecord.fromValue`, `AgentTaskValue.fromValue`, which name the
// field at fault), and their closed sets are mapped here, each by one
// exhaustive switch. A record that does not decode is [Invalid]; the caller
// shows it, it never becomes an empty task.

/// `tasks/<id>` `~state` of the agent link as an [AgentTask].
Decoded<AgentTask> agentTaskOf(String id, Value v) {
  try {
    return Valid(taskOfRecord(id, AgentTaskRecord.fromValue(v)));
  } on DecodeError catch (e) {
    return Invalid(
      'agent task',
      e.path,
      'expected ${e.expected}, got ${e.got}',
    );
  }
}

/// A task's public `~val` (`{state, step, of, last?, suggestions?,
/// findings?, reviewing?, replaced_by?}`).
Decoded<AgentTaskValue> agentTaskValueOf(Value v) {
  try {
    return Valid(AgentTaskValue.fromValue(v));
  } on DecodeError catch (e) {
    return Invalid(
      'agent task value',
      e.path,
      'expected ${e.expected}, got ${e.got}',
    );
  }
}

/// The decoded record [r] of task [id]. The plan's hash is the one made
/// here from the plan as read ([AgentTaskRecord.shownPlanHash]), never the
/// link's own `plan_hash`: an approval names the plan that is shown.
AgentTask taskOfRecord(String id, AgentTaskRecord r) => AgentTask(
  id: id,
  state: taskStateOf(r.state),
  owner: r.owner,
  ask: r.ask,
  plan: [for (final s in r.plan) _step(s)].lock,
  planHash: r.shownPlanHash,
  questions: [for (final q in r.questions) _question(q)].lock,
  step: r.step,
  parent: r.parent,
  log: r.log.lock,
  error: r.error,
  tokens: r.tokens,
  suggestions: [
    for (final s in r.suggestions)
      TaskSuggestion(
        id: s.id,
        label: s.label,
        detail: s.detail,
        changes: s.changes,
        step: s.step,
        rows: [
          for (final row in s.rows)
            TaskRow(key: row.key, label: row.label, detail: row.detail),
        ].lock,
      ),
  ].lock,
  replacedBy: r.replacedBy,
  review: r.review,
  reviewing: r.reviewing,
  findings: [
    for (final f in r.findings)
      TaskFinding(key: f.key, label: f.label, detail: f.detail),
  ].lock,
  findingsRefused: {
    for (final e in r.findingsRefused.entries) _refusal(e.key): e.value,
  }.lock,
  approvedBy: _approvedBy(r.log),
  told: _told(r.ask, r.log),
  recorded: true,
);

/// The task states of the agent link.
TaskState taskStateOf(AgentTaskState s) => switch (s) {
  AgentTaskState.planning => TaskState.planning,
  AgentTaskState.awaitingApproval => TaskState.awaitingApproval,
  AgentTaskState.running => TaskState.running,
  AgentTaskState.done => TaskState.done,
  AgentTaskState.failed => TaskState.failed,
  AgentTaskState.awaitingAnswer => TaskState.awaitingAnswer,
};

FindingRefusal _refusal(AgentFindingRefusal r) => switch (r) {
  AgentFindingRefusal.rightsUnknown => FindingRefusal.rightsUnknown,
  AgentFindingRefusal.rightsExpired => FindingRefusal.rightsExpired,
  AgentFindingRefusal.outsideRights => FindingRefusal.outsideRights,
  AgentFindingRefusal.limit => FindingRefusal.limit,
  AgentFindingRefusal.invalid => FindingRefusal.invalid,
};

StepKind _kind(AgentStepKind k) => switch (k) {
  AgentStepKind.set => StepKind.set,
  AgentStepKind.invoke => StepKind.invoke,
  AgentStepKind.wait => StepKind.wait,
  AgentStepKind.expect => StepKind.expect,
  AgentStepKind.sleep => StepKind.sleep,
};

StepCheck _check(AgentStepCheck c) => switch (c) {
  AgentStepCheck.now => StepCheck.now,
  AgentStepCheck.atRun => StepCheck.atRun,
};

StepStatus _status(AgentStepStatus s) => switch (s) {
  AgentStepStatus.ok => StepStatus.ok,
  AgentStepStatus.failed => StepStatus.failed,
  AgentStepStatus.skipped => StepStatus.skipped,
};

/// One step of the plan. Its arguments are what the step sends, whole:
/// `set` its value, `invoke` its arguments, `expect` its test (`equals`,
/// `min`/`max`, `changes`). They are any value an action takes (no schema
/// here), so they are kept as plain Dart values, converted once, here.
PlanStep _step(AgentPlanStep s) => PlanStep(
  kind: _kind(s.kind),
  key: s.node ?? '',
  n: s.n,
  action: s.action,
  args: switch (s.kind) {
    AgentStepKind.set => {'value': toDart(s.value)},
    AgentStepKind.invoke => switch (toDart(s.args)) {
      final Map<String, Object?> m => m,
      null => const <String, Object?>{},
      final Object o => {'value': o},
    },
    AgentStepKind.expect => {
      if (s.equals case final e?) 'equals': toDart(e),
      'min': ?s.min,
      'max': ?s.max,
      if (s.changes) 'changes': true,
    },
    AgentStepKind.wait || AgentStepKind.sleep => const <String, Object?>{},
  }.lock,
  seconds: s.seconds,
  level: s.level,
  approval: s.approval,
  check: _check(s.check),
  warn: s.warn,
  modelWarn: s.modelWarn,
  after: s.after.lock,
  reason: s.reason,
  result: switch (s.result) {
    null => null,
    final AgentStepResult r => StepResult(
      status: _status(r.status),
      message: r.message,
      code: refusalCode(r.message),
      time: r.time > 0
          ? DateTime.fromMillisecondsSinceEpoch(r.time * 1000)
          : null,
    ),
  },
);

/// The fixed word a link's refusal starts with: `out_of_range` of
/// `out_of_range: 21.5 is above max 21`; null when the text has none.
String? refusalCode(String text) =>
    RegExp('^([a-z][a-z0-9_]*):').firstMatch(text)?[1];

/// A question of `~state.questions[]`; its answer is the picked option ids
/// or the person's own words.
TaskQuestion _question(AgentQuestion q) => TaskQuestion(
  id: q.id,
  text: q.text,
  options: [
    for (final o in q.options)
      TaskOption(id: o.id, label: o.label, detail: o.detail),
  ].lock,
  multiple: q.multiple,
  freeText: q.freeText,
  answered: q.answer != null,
  picked: switch (q.answer) {
    AgentAnswerOptions(:final ids) => ids.lock,
    _ => const IListConst([]),
  },
  words: switch (q.answer) {
    AgentAnswerText(:final text) => text,
    _ => null,
  },
);

/// `approved by olena, 1 step(s) left out`: the record's own line, the
/// subject without its `user:`.
String? _approvedBy(List<String> log) => log
    .where((l) => l.startsWith('approved by '))
    .map((l) => l.replaceFirst('approved by user:', 'approved by '))
    .lastOrNull;

/// The conversation of a task asked in another session (or before a
/// restart of Studio), from its record: the ask, then the log (`model: …`
/// lines as the model's, `failed: …` as the error, the rest as what it
/// did).
IList<TaskEvent> _told(String ask, List<String> log) => [
  if (ask.isNotEmpty) TaskEvent(kind: TaskEventKind.ask, text: ask),
  for (final l in log)
    if (l.startsWith('model: '))
      TaskEvent(kind: TaskEventKind.text, text: l.substring(7))
    else if (l.startsWith('failed: '))
      TaskEvent(kind: TaskEventKind.error, text: l.substring(8))
    else if (!l.startsWith('asked by '))
      TaskEvent(kind: TaskEventKind.note, text: l),
].lock;
