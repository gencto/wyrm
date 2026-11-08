import 'package:models/links_tab.dart';

import '../../app_state.dart';
import '../../common/action.dart';

class SetTabAction extends Action {
  SetTabAction(this.tab);

  final LinksTab tab;

  @override
  AppState reduce() => state.copyWith.links(tab: tab);
}
