import 'dart:async';

import 'package:async_redux/async_redux.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../../wyrm/calls.dart';
import '../../../wyrm/mappers/flow_mapper.dart';
import '../../../wyrm/mappers/values.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import '../../flows/actions/retrieve_flows_action.dart';

/// `dataflows` ▸ `deploy {def}` (config) with `version + 1` and the
/// layout; the gateway adds the deployer's proofs (ADR 0008, 0033).
class DeployFlowAction extends Action with NonReentrant, WaitingAction {
  @override
  Future<AppState?> reduce() async {
    final d = flowEditor.draft;
    final root = site.root;
    if (d == null || root == null) {
      return null;
    }
    final v = flowEditor.version + 1;
    await invokeAll(
      deps.wyrm,
      '$root/dataflows',
      'deploy',
      Value.from({'def': toDart(defOf(d, v))}),
    );
    return state.copyWith.flowEditor(
      version: v,
      dirty: false,
      message: 'deployed version $v',
      draft: d.copyWith(version: v),
    );
  }

  @override
  void after() {
    super.after();
    unawaited(dispatchAndWait(RetrieveFlowsAction()));
  }
}
