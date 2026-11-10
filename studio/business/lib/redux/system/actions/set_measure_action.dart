import '../../app_state.dart';
import '../../common/action.dart';

class SetMeasureAction extends Action {
  SetMeasureAction(this.measure);

  final String measure;

  @override
  AppState reduce() => state.copyWith.system(measure: measure);
}
