import '../../app_state.dart';
import '../../common/action.dart';

class SetSelectedFlowAction extends Action {
  SetSelectedFlowAction(this.selectedFlow);

  final String? selectedFlow;

  @override
  AppState reduce() => state.copyWith.flows(selectedFlow: selectedFlow);
}
