import '../../app_state.dart';
import '../../common/action.dart';
import 'retrieve_access_action.dart';
import 'set_shown_action.dart';

/// Access comes on screen: it is marked shown (its 10 s read runs while it
/// is) and read. The mark changes nothing Access draws (`notify: false`);
/// the read notifies for what it changes. Changes no state itself.
class ShowAccessAction extends Action {
  @override
  Future<AppState?> reduce() async {
    dispatchSync(SetShownAction(true), notify: false);
    await dispatchAndWait(RetrieveAccessAction());
    return null;
  }
}
