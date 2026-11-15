import '../../app_state.dart';
import '../../common/action.dart';
import '../../updates/actions/open_update_action.dart';

/// *Update all official…*: the update sheet of the first official package
/// with a newer version, the others queued after it. Null when there is
/// none.
class UpdateAllOfficialAction extends Action {
  @override
  AppState? reduce() {
    final names = updatablePackages;
    if (names.isEmpty) {
      return null;
    }
    dispatchSync(OpenUpdateAction(names.first, queue: names.sublist(1)));
    return null;
  }
}
