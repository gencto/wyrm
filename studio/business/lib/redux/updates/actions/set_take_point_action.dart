import '../../app_state.dart';
import '../../common/action.dart';

class SetTakePointAction extends Action {
  SetTakePointAction(this.takePoint);

  final bool takePoint;

  @override
  AppState reduce() => state.copyWith.updates(takePoint: takePoint);
}
