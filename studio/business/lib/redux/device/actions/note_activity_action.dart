import '../../app_state.dart';
import '../../common/action.dart';

/// The person used Studio (a pointer or a key in the shell, throttled by the
/// shell): the idle lock's clock starts again. Changes no state.
class NoteActivityAction extends Action {
  @override
  AppState? reduce() {
    if (!state.device.locked) {
      deps.idleLock.touch();
    }
    return null;
  }
}
