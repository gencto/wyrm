import '../../app_state.dart';
import '../../common/action.dart';
import 'sync_view_action.dart';

/// Back: the page before this one in the stack.
class BackViewPageAction extends Action with SyncsView {
  @override
  AppState? reduce() {
    if (views.stack.length < 2) {
      return null;
    }
    syncView = resetView = true;
    return state.copyWith.views(stack: views.stack.removeLast());
  }
}
