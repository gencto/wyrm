import '../../app_state.dart';
import '../../common/action.dart';

class SetLinesAction extends Action {
  SetLinesAction(this.lines);

  final int lines;

  @override
  AppState reduce() => state.copyWith.system(lines: lines);
}
