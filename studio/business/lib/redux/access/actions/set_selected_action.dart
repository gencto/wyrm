import '../../app_state.dart';
import '../../common/action.dart';

class SetSelectedAction extends Action {
  SetSelectedAction(this.selected);

  final String? selected;

  @override
  AppState reduce() => state.copyWith.access(selected: selected);
}
