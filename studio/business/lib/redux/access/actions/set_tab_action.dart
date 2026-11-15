import 'package:models/access_tab.dart';

import '../../app_state.dart';
import '../../common/action.dart';

class SetTabAction extends Action {
  SetTabAction(this.tab);

  final AccessTab tab;

  @override
  AppState reduce() => state.copyWith.access(tab: tab);
}
