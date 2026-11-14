import '../../app_state.dart';
import '../../common/action.dart';

class SetRangePortAction extends Action {
  SetRangePortAction(this.rangePort);

  final String? rangePort;

  @override
  AppState reduce() => state.copyWith.discovery(rangePort: rangePort);
}
