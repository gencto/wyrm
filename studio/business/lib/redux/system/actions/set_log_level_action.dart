import 'package:models/log_level.dart';

import '../../app_state.dart';
import '../../common/action.dart';

class SetLogLevelAction extends Action {
  SetLogLevelAction(this.logLevel);

  final LogLevel? logLevel;

  @override
  AppState reduce() => state.copyWith.system(logLevel: logLevel);
}
