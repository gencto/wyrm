import '../../app_state.dart';
import '../../common/action.dart';
import 'load_flow_action.dart';

/// The flow on screen was deployed again (its watch heard a new version):
/// a draft that differs from the deployed version is kept; else the new
/// version is read, so the blocks match their live values. It changes no
/// state itself (`null`); the read brings its own.
class ReloadRedeployedFlowAction extends Action {
  @override
  Future<AppState?> reduce() async {
    final id = flowEditor.flowId;
    if (id != null && id.isNotEmpty && !flowEditor.dirty) {
      await dispatchAndWait(LoadFlowAction(id));
    }
    return null;
  }
}
