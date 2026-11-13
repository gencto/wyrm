import '../../app_state.dart';
import '../../common/action.dart';
import 'check_view_action.dart';

/// What the broker said about keys the view reads (key → `ok` or the
/// status that refused it); the checks run again.
class AddViewKeysAction extends Action {
  AddViewKeysAction(this.states);

  final Map<String, String> states;

  @override
  AppState? reduce() {
    if (!views.open) {
      return null;
    }
    return state.copyWith.views(keys: views.keys.addMap(states));
  }

  @override
  void after() {
    super.after();
    dispatchSync(CheckViewAction());
  }
}
