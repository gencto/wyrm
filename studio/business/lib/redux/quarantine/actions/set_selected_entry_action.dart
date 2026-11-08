import '../../app_state.dart';
import '../../common/action.dart';

class SetSelectedEntryAction extends Action {
  SetSelectedEntryAction(this.selectedEntry);

  final String? selectedEntry;

  @override
  AppState reduce() => state.copyWith.quarantine(selectedEntry: selectedEntry);
}
