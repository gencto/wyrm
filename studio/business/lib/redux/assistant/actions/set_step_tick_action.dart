import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import '../../app_state.dart';
import '../../common/action.dart';

/// Ticks or unticks step [n] of the plan of [task]. Every step that needs
/// the person starts ticked, so only the unticked ones are kept. A refusal
/// of the last approval is forgotten: the choice it was about has changed.
class SetStepTickAction extends Action {
  SetStepTickAction(this.task, this.n, {required this.ticked});

  final String task;
  final int n;
  final bool ticked;

  @override
  AppState reduce() {
    final was = assistant.unticked[task] ?? const ISetConst<int>({});
    final now = ticked ? was.remove(n) : was.add(n);
    return state.copyWith.assistant(
      unticked: now.isEmpty
          ? assistant.unticked.remove(task)
          : assistant.unticked.add(task, now),
      refusals: assistant.refusals.remove(task),
    );
  }
}
