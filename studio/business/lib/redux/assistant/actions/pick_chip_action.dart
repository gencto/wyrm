import '../../../wyrm/context_keys.dart';
import '../../app_state.dart';
import '../../common/action.dart';

/// A key was picked in *+ from Explorer* (offered, or typed in full or
/// below the site): it becomes an `@` chip when, now that the picker has
/// closed, it still names a plain node key of the site on screen that the
/// agent reads and is no chip yet, and there is room for one more
/// ([maxContextKeys]). Anything else changes nothing.
class PickChipAction extends Action {
  PickChipAction(this.picked);

  final String picked;

  @override
  AppState? reduce() {
    final chips = assistant.chips;
    final typed = typedChip(picked);
    if (typed == null || !typed.reads || chips.length >= maxContextKeys) {
      return null;
    }
    return state.copyWith.assistant(chips: chips.add(typed.key));
  }
}
