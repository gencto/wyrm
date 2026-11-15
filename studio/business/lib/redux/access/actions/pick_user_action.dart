import '../../app_state.dart';
import '../../common/action.dart';
import '../../device/actions/retrieve_user_devices_action.dart';
import 'set_selected_action.dart';

/// A user picked in Access › Users: the inspector shows them at once; their
/// devices are read by their own action, which notifies when they come.
class PickUserAction extends Action {
  PickUserAction(this.name);

  final String name;

  @override
  Future<AppState?> reduce() async {
    dispatchSync(SetSelectedAction(name));
    await dispatchAndWait(RetrieveUserDevicesAction(name, quiet: true));
    return null;
  }
}
