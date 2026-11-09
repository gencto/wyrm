import 'package:models/link_mode.dart';

import '../../app_state.dart';
import '../../common/action.dart';

class SetModeAction extends Action {
  SetModeAction(this.mode);

  final LinkMode? mode;

  @override
  AppState reduce() => state.copyWith.linkInstall(mode: mode);
}
