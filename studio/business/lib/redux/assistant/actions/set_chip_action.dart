import '../../app_state.dart';
import '../../common/action.dart';

/// Adds the node [key] to the composer's `@` chips, or with [on] false
/// takes it away. The chips go with the next ask as its `context`.
class SetChipAction extends Action {
  SetChipAction(this.key, {this.on = true});

  final String key;
  final bool on;

  @override
  AppState? reduce() {
    final chips = assistant.chips;
    if (on == chips.contains(key)) {
      return null;
    }
    return state.copyWith.assistant(
      chips: on ? chips.add(key) : chips.remove(key),
    );
  }
}
