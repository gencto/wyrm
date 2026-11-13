import '../../app_state.dart';
import '../../common/action.dart';

class SetWidthAction extends Action {
  SetWidthAction(this.width);

  final String width;

  @override
  AppState reduce() => state.copyWith.views(width: width);
}
