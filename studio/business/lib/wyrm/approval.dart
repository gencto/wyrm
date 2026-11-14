import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/plan_step.dart';

/// What the person decides for one step of a plan that waits (ADR 0049
/// §2–4).
final class StepChoice {
  const StepChoice({required this.n, this.ticked, this.locked, this.needs});

  /// The step's number in the plan, from 1.
  final int n;

  /// The step's tick: null when the person signs nothing for it (it reads
  /// only, or it runs with the agent's key).
  final bool? ticked;

  /// Why the tick cannot be set: the level the user lacks on the step's
  /// request key.
  final String? locked;

  /// The step it needs (`after`) that is left out: this one is skipped
  /// with it.
  final int? needs;

  /// The run leaves the step out.
  bool get skipped => needs != null || ticked == false;
}

/// The key a step's token is good for: `<node>/~set` or
/// `<node>/~act/<action>` (the gateway signs one token per request key).
String requestKey(PlanStep s) =>
    s.op == 'set' ? '${s.key}/~set' : '${s.key}/~act/${s.action ?? ''}';

/// The choices of [plan], in its order.
///
/// A step that changes something has a tick when it needs a human
/// (`approval`), and always when the person does not decide for the task
/// ([decides]: the asker, or a user with `config` on the agent link):
/// such a person runs only what they sign. [lacks] says why the user may
/// not sign a step (`level`, request key), or null. A step whose `after`
/// names a step that is left out is left out too.
List<StepChoice> approvalOf(
  Iterable<PlanStep> plan, {
  required ISet<int> unticked,
  required bool decides,
  required String? Function(String level, String key) lacks,
}) {
  final out = <StepChoice>[];
  final skipped = <int>{};
  for (final s in plan) {
    final changes = s.op == 'set' || s.op == 'invoke';
    final signs = changes && (s.approval || !decides);
    final locked = signs ? lacks(s.level, requestKey(s)) : null;
    final needs = s.after.where(skipped.contains).firstOrNull;
    final choice = StepChoice(
      n: s.n,
      ticked: signs
          ? locked == null && needs == null && !unticked.contains(s.n)
          : null,
      locked: locked,
      needs: needs,
    );
    if (choice.skipped) {
      skipped.add(s.n);
    }
    out.add(choice);
  }
  return out;
}
