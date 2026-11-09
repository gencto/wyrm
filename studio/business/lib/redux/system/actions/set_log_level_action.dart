import '../../app_state.dart';
import '../../common/action.dart';

class SetLogLevelAction extends Action {
  SetLogLevelAction(this.logLevel);

  final String? logLevel;

  @override
  AppState reduce() => state.copyWith.system(logLevel: logLevel);
}
