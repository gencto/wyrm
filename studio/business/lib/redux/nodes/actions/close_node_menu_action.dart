import '../../app_state.dart';
import '../../common/action.dart';

/// The node menu closed without a pick.
class CloseNodeMenuAction extends Action {
  @override
  AppState? reduce() =>
      nodes.menu == null ? null : state.copyWith.nodes(menu: null);
}
