import '../../app_state.dart';
import '../../common/action.dart';

class SetSourceAction extends Action {
  SetSourceAction(this.source);

  final String? source;

  @override
  AppState reduce() => state.copyWith.system(source: source);
}
