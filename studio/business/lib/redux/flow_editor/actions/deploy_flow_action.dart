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
  Action again() => DeployFlowAction();

  @override
  Action reload() => RetrieveFlowsAction();

  @override
  Future<AppState?> reduce() async {
    final d = flowEditor.draft;
    final root = site.root;
    // Deploy is off while the canvas shows the inside of a block (the page
    // says why): the draft here is the block's, not the flow's.
    if (d == null || root == null || flowEditor.frames.isNotEmpty) {
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
      deployed: d.copyWith(version: v),
    );
  }

  /// The flows list learns the new version. While Flows follows
  /// `dataflows` (its tab shown under the editor), the live `~val` brings
  /// it and reads this flow's definition alone; else one full read.
  @override
  void after() {
    super.after();
    if (flows.follow == null) {
      unawaited(dispatchAndWait(RetrieveFlowsAction()));
    }
  }
}
