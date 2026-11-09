import '../../app_state.dart';
import '../../common/action.dart';

class SetSelectedNodeAction extends Action {
  SetSelectedNodeAction(this.selectedNode);

  final String? selectedNode;

  @override
  AppState reduce() => state.copyWith.nodes(selectedNode: selectedNode);
}
