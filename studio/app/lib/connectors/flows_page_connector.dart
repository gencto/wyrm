import 'package:async_redux/async_redux.dart';
import 'package:auto_route/auto_route.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/flows/actions/follow_flows_action.dart';
import 'package:business/redux/flows/actions/set_selected_flow_action.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/pages/flows_page.dart';
import 'package:wyrm_client/wyrm_client.dart' show Perm;

import '../common/tab_visibility.dart';
import '../mappers/flow_mappers.dart';
import '../mappers/rights_mappers.dart';
import '../navigation/app_router.dart';
import '../navigation/go_action.dart';

/// The id the editor route takes for a flow not made yet.
const newFlowId = '+new';

/// Flows: the site's flows from the live list of `dataflows`, mapped
/// through `app/lib/mappers/flow_mappers.dart`; `FlowsPage` words them.
/// One action per intent.
@RoutePage()
class FlowsPageConnector extends StatelessWidget {
  const FlowsPageConnector({super.key});

  @override
  Widget build(BuildContext context) => StoreConnector<AppState, _Vm>(
    debug: this,
    vm: () => _Factory(this),
    builder: (context, vm) => TabVisibility(
      onShow: vm.onShow,
      onHide: vm.onHide,
      child: FlowsPage(
        vm: vm.page,
        onNew: vm.onNew,
        onRow: vm.onRow,
        onEdit: vm.onEdit,
      ),
    ),
  );
}

/// Factory that creates a view-model for the StoreConnector.
class _Factory extends VmFactory<AppState, FlowsPageConnector, _Vm>
    with Selectors {
  _Factory(super._connector);

  @override
  _Vm fromStore() {
    final root = site.root ?? '';
    final picked = flows.picked;
    final key = '$root/dataflows/${picked?.id}';
    return _Vm(
      page: FlowsVm(
        site: site.viewed ?? '',
        flows: [for (final f in flows.shown) f.row],
        picked: picked?.id,
        pickedKey: key,
        newDisabled: site.lacks(Perm.config, '$root/dataflows')?.disabled,
        editDisabled: picked == null
            ? null
            : site.lacks(Perm.read, key)?.disabled,
      ),
      // The live list of `dataflows` fills and keeps the table; a
      // definition is read only for a new flow or a new version.
      onShow: () => dispatchSync(FollowFlowsAction(show: true)),
      onHide: () => dispatchSync(FollowFlowsAction(show: false)),
      onRow: (id) => dispatchSync(SetSelectedFlowAction(id)),
      onNew: () => dispatch(GoAction.push(FlowEditorRoute(id: newFlowId))),
      onEdit: (id) => dispatch(GoAction.push(FlowEditorRoute(id: id))),
    );
  }
}

/// What Flows draws ([page], compared) and what it starts (not).
class _Vm extends Vm {
  _Vm({
    required this.page,
    required this.onShow,
    required this.onHide,
    required this.onRow,
    required this.onNew,
    required this.onEdit,
  }) : super(equals: [page]);

  final FlowsVm page;
  final VoidCallback onShow;
  final VoidCallback onHide;
  final ValueChanged<String> onRow;
  final VoidCallback onNew;
  final ValueChanged<String> onEdit;
}
