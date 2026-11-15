import 'package:models/system_tab.dart';

import '../../app_state.dart';
import '../../common/action.dart';

class SetTabAction extends Action {
  SetTabAction(this.tab);

  final SystemTab tab;

  @override
  AppState reduce() => state.copyWith.system(tab: tab);
}
