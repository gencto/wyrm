import '../../app_state.dart';
import '../../common/action.dart';

class SetDensityAction extends Action {
  SetDensityAction(this.density);

  final String? density;

  @override
  AppState reduce() => state.copyWith.views(density: density);
}
