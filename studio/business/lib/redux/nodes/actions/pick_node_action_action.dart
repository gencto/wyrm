import 'package:models/explorer_tab.dart';

import '../../app_state.dart';
import '../../common/action.dart';

/// An action is picked in the node menu: the Actions tab with its form,
/// the menu closed, in one state.
class PickNodeActionAction extends Action {
  PickNodeActionAction(this.action);

  final String action;

  @override
  AppState? reduce() => state.copyWith.nodes(
    tab: ExplorerTab.actions,
    action: action,
    menu: null,
  );
}
