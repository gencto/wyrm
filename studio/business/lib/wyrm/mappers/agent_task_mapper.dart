import 'dart:convert';
import 'dart:typed_data';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/agent_task.dart';
import 'package:models/plan_step.dart';
import 'package:models/step_check.dart';
import 'package:models/step_kind.dart';
import 'package:models/task_row.dart';
import 'package:models/task_suggestion.dart';
import 'package:models/withheld_args.dart';
import 'package:wyrm_client/wyrm_client.dart' as wc;

// What is made from a decoded task (`decode/agent_task.dart`): the text of
// a follow-up ask, the plan as a file for `wyrm-agent run`, the arguments a
// file leaves out, how far a plan was checked.

/// The text of the follow-up ask for [s] (what the person saw on the
/// card) and the labels of the [picked] rows: as `wyrm_client` makes it.
String suggestionAsk(TaskSuggestion s, Iterable<TaskRow> picked) =>
    _wire(s).ask([for (final r in picked) _wireRow(r)]);

wc.TaskSuggestion _wire(TaskSuggestion s) => wc.TaskSuggestion(
  id: s.id,
  label: s.label,
  detail: s.detail,
  changes: s.changes,
  step: s.step,
  rows: [for (final r in s.rows) _wireRow(r)],
);

wc.TaskRow _wireRow(TaskRow r) =>
    wc.TaskRow(key: r.key, label: r.label, detail: r.detail);

/// The plan of [t] as a file for `wyrm-agent run` (`{"steps": […]}`,
/// docs/agent.md): each step as it stands in the record, without what is
/// said about it (number, level, check, reason, result). A secret argument
/// (`PlanStep.secret`), and any argument of a step whose schema is not
/// known ([withheld]), is never written: `secrets_left_out` names it, and
/// the person adds it before the plan is run.
Map<String, Object?> planFile(AgentTask t) => {
  'about': t.ask,
  if (secretsLeftOut(t) case final left when left.isNotEmpty)
    'secrets_left_out': left,
  'steps': [
    for (final s in t.plan)
      switch (s.kind) {
        StepKind.set => {'set': s.key, 'value': s.args['value']},
        StepKind.invoke => {
          'invoke': s.key,
          'action': s.action ?? '',
          'args': {
            for (final e in s.args.entries)
              if (!withheld(s).contains(e.key)) e.key: e.value,
          },
        },
        StepKind.wait => {'wait': s.key, 'timeout_s': s.seconds ?? 10},
        StepKind.expect => {
          'expect': s.key,
          ...s.args.unlock,
          'timeout_s': s.seconds ?? 10,
        },
        StepKind.sleep => {'sleep_s': s.seconds ?? 0},
      },
  ],
};

/// The arguments Save as a plan leaves out of the file of [t]'s plan, by
/// step: the screen's notice names them.
IList<WithheldArgs> withheldOf(AgentTask t) => [
  for (final s in t.plan)
    if (withheld(s) case final w when w.isNotEmpty)
      WithheldArgs(step: s.n, names: w.lock),
].lock;

/// [withheldOf] as the plan file names it (`secrets_left_out`, a field of
/// the `wyrm-agent run` format): `step <n>: <arg>, …`, one per step.
List<String> secretsLeftOut(AgentTask t) => [
  for (final w in withheldOf(t)) 'step ${w.step}: ${w.names.join(', ')}',
];

/// The arguments of [s] that are never written to a file and are masked
/// on screen: the secret ones, and every one of a step whose schema is not
/// known ([PlanStep.argsKnown]: any of them may be a secret). The order is
/// the step's own.
List<String> withheld(PlanStep s) => [
  for (final name in s.args.keys)
    if (!s.argsKnown || s.secret.contains(name)) name,
];

/// How far the steps of [plan] that change something were checked: how
/// many against the live tree now, and how many only when they run
/// (`check: at_run`: an earlier step makes their node).
({int now, int atRun}) planChecks(Iterable<PlanStep> plan) {
  final changing = plan.where((s) => s.kind.changes);
  final atRun = changing.where((s) => s.check == StepCheck.atRun).length;
  return (now: changing.length - atRun, atRun: atRun);
}

/// A value of a step as it is sent, whole: text as it is, anything else as
/// JSON.
String argText(Object? v) => switch (v) {
  final String s => s,
  _ => jsonEncode(v, toEncodable: _bytes),
};

/// Binary in a value: its length (JSON has no bytes).
Object? _bytes(Object? v) => v is Uint8List ? '<${v.length} bytes>' : '$v';
