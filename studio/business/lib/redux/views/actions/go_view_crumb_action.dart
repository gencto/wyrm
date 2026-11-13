import '../../app_state.dart';
import '../../common/action.dart';
import 'sync_view_action.dart';

/// A tap on breadcrumb [index]: the stack is cut back to it.
class GoViewCrumbAction extends Action with SyncsView {
  GoViewCrumbAction(this.index);

  final int index;

  @override
  AppState? reduce() {
    if (index < 0 || index >= views.stack.length - 1) {
      return null;
    }
    syncView = resetView = true;
    return state.copyWith.views(stack: views.stack.sublist(0, index + 1));
  }
}
