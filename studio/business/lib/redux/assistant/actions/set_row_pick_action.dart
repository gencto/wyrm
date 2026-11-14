import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import '../../app_state.dart';
import '../../common/action.dart';

/// Ticks or unticks the row [key] of the suggestion [suggestion] of
/// [task] (*Same for more units?*). Rows start unticked: the person picks
/// the nodes the follow-up is for.
class SetRowPickAction extends Action {
  SetRowPickAction(this.task, this.suggestion, this.key, {required this.on});

  final String task;
  final String suggestion;
  final String key;
  final bool on;

  @override
  AppState reduce() {
    final at = '$task/$suggestion';
    final was = assistant.rowPicks[at] ?? const ISetConst<String>({});
    final now = on ? was.add(key) : was.remove(key);
    return state.copyWith.assistant(
      rowPicks: now.isEmpty
          ? assistant.rowPicks.remove(at)
          : assistant.rowPicks.add(at, now),
    );
  }
}
