import '../../app_state.dart';
import '../../common/action.dart';
import '../../flows/actions/retrieve_flows_action.dart';
import 'deploy_flow_action.dart';

/// Deploy on the editor's page: the draft deployed ([DeployFlowAction],
/// its own wait: the page says `deploying` while it runs), then the flows
/// list learns the new version. While Flows follows `dataflows` (its tab
/// shown under the editor) the live `~val` brings it; else one full read,
/// the last step of the press. It changes no state itself (`null`).
class DeployShownFlowAction extends Action {
  @override
  Future<AppState?> reduce() async {
    final deployed = await dispatchAndWait(DeployFlowAction());
    if (deployed.isCompletedOk && flows.follow == null) {
      await dispatchAndWait(RetrieveFlowsAction());
    }
    return null;
  }
}
