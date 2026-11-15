import 'package:models/explorer_tab.dart';

import '../../app_state.dart';
import '../../common/action.dart';

/// The tab of the node on screen in Explorer.
class SetTabAction extends Action {
  SetTabAction(this.tab);

  final ExplorerTab tab;

  @override
  AppState reduce() => state.copyWith.nodes(tab: tab);
}
