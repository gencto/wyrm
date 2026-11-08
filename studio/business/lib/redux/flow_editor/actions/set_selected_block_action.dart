import '../../app_state.dart';
import '../../common/action.dart';

class SetSelectedBlockAction extends Action {
  SetSelectedBlockAction(this.selectedBlock);

  final String? selectedBlock;

  @override
  AppState reduce() => state.copyWith.flowEditor(selectedBlock: selectedBlock);
}
