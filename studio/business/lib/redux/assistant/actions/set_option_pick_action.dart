import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import '../../app_state.dart';
import '../../common/action.dart';

/// Picks [option] of [question] of [task] on the choices card, or takes
/// the pick back. A question that takes one option ([multiple] false)
/// keeps the latest pick only. Picks are kept by `<task>/<question>`.
class SetOptionPickAction extends Action {
  SetOptionPickAction(
    this.task,
    this.question,
    this.option, {
    required bool this.multiple,
  });

  /// Whether the question takes several options is read from the task.
  SetOptionPickAction.of(this.task, this.question, this.option)
    : multiple = null;

  final String task;
  final String question;
  final String option;
  final bool? multiple;

  @override
  AppState? reduce() {
    final multiple =
        this.multiple ??
        tasks.table[task]?.questions
            .where((q) => q.id == question)
            .firstOrNull
            ?.multiple;
    if (multiple == null) {
      return null;
    }
    final key = '$task/$question';
    final was = assistant.picks[key] ?? const ISetConst<String>({});
    final now = was.contains(option)
        ? was.remove(option)
        : (multiple ? was.add(option) : {option}.lock);
    return state.copyWith.assistant(
      picks: now.isEmpty
          ? assistant.picks.remove(key)
          : assistant.picks.add(key, now),
    );
  }
}
