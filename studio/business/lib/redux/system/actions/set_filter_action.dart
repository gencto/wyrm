import '../../app_state.dart';
import '../../common/action.dart';

class SetFilterAction extends Action {
  SetFilterAction(this.filter);

  final String? filter;

  @override
  AppState reduce() => state.copyWith.system(filter: filter);
}
