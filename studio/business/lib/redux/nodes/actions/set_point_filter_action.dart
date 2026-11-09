import '../../app_state.dart';
import '../../common/action.dart';

class SetPointFilterAction extends Action {
  SetPointFilterAction(this.pointFilter);

  final String pointFilter;

  @override
  AppState reduce() => state.copyWith.nodes(pointFilter: pointFilter);
}
