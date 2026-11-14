import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import '../../app_state.dart';
import '../../common/action.dart';

/// Shows or masks again the arguments of step [n] of the plan of [task]
/// whose schema is not known (`PlanStep.argsKnown` false: any of them may
/// be a secret). A known secret argument is never shown.
class SetStepRevealAction extends Action {
  SetStepRevealAction(this.task, this.n, {required this.shown});

  final String task;
  final int n;
  final bool shown;

  @override
  AppState reduce() {
    final was = assistant.revealed[task] ?? const ISetConst<int>({});
    final now = shown ? was.add(n) : was.remove(n);
    return state.copyWith.assistant(
      revealed: now.isEmpty
          ? assistant.revealed.remove(task)
          : assistant.revealed.add(task, now),
      // a refusal of the last approval was about what was shown
      refusals: assistant.refusals.remove(task),
    );
  }
}
