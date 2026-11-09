import '../../app_state.dart';
import '../../common/action.dart';

class SetViewedPointAction extends Action {
  SetViewedPointAction(this.viewedPoint);

  final String? viewedPoint;

  @override
  AppState reduce() => state.copyWith.nodes(viewedPoint: viewedPoint);
}
