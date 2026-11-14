import '../../app_state.dart';
import '../../common/action.dart';

class SetRangeAction extends Action {
  SetRangeAction(this.range);

  final String? range;

  @override
  AppState reduce() => state.copyWith.discovery(range: range);
}
