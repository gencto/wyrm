import '../../app_state.dart';
import '../../common/action.dart';

class SetAutoAction extends Action {
  SetAutoAction(this.auto);

  final bool auto;

  @override
  AppState reduce() => state.copyWith.system(auto: auto);
}
