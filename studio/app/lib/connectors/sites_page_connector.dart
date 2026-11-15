import 'dart:async';

import 'package:async_redux/async_redux.dart';
import 'package:auto_route/auto_route.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/live/actions/unwatch_keys_action.dart';
import 'package:business/redux/peers/actions/set_selected_peer_action.dart';
import 'package:business/redux/peers/actions/show_sites_action.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/pages/sites_page.dart';

import '../common/tab_visibility.dart';
import '../dialogs/sites_dialogs.dart';
import '../mappers/rights_mappers.dart';
import '../mappers/sites_mappers.dart';
import '../navigation/sites_go_action.dart';

/// Sites: the map around the site on screen and the inspector of the node
/// picked, computed in business (`peers.siteMap`, `peers.siteDetail`) and
/// mapped through `app/lib/mappers/sites_mappers.dart`; `SitesPage` words
/// them.
/// One action per intent; the forms and confirmations open from the
/// widget, with the widget's context (`app/lib/dialogs/sites_dialogs.dart`).
@RoutePage()
class SitesPageConnector extends StatelessWidget {
  const SitesPageConnector({super.key});

  @override
  Widget build(BuildContext context) => StoreConnector<AppState, _Vm>(
    debug: this,
    vm: () => _Factory(this),
    builder: (context, vm) => TabVisibility(
      onShow: vm.onShow,
      onHide: vm.onHide,
      child: SitesPage(
        vm: vm.page,
        onNode: vm.onNode,
        onGo: vm.onGo,
        onConnect: () => unawaited(connectUpstream(context)),
        onToken: () => unawaited(issueToken(context)),
        onDeauthorize: () => unawaited(deauthorizeBroker(context)),
        onApprove: (values) => approveBroker(context, values),
        onReject: () => unawaited(rejectWaiting(context)),
      ),
    ),
  );
}

/// Factory that creates a view-model for the StoreConnector.
class _Factory extends VmFactory<AppState, SitesPageConnector, _Vm>
    with Selectors {
  _Factory(super._connector);

  @override
  _Vm fromStore() {
    final keys = peers.sitesKeys;
    return _Vm(
      page: SitesVm(
        site: site.viewed ?? '',
        nodes: [for (final n in peers.siteMap) n.data],
        waiting: peers.sitesWaiting,
        detail: peers.siteDetail?.vm,
        lack: peers.sitesLack?.disabled,
        busy: peers.isWaiting || quarantine.isWaiting,
      ),
      onShow: () => dispatch(ShowSitesAction()),
      onHide: () => dispatchSync(UnwatchKeysAction(keys)),
      onNode: (ref) => dispatchSync(SetSelectedPeerAction(ref.pick)),
      onGo: (go) => dispatch(SitesGoAction(go)),
    );
  }
}

/// What Sites draws ([page], compared) and what it starts (not).
class _Vm extends Vm {
  _Vm({
    required this.page,
    required this.onShow,
    required this.onHide,
    required this.onNode,
    required this.onGo,
  }) : super(equals: [page]);

  final SitesVm page;
  final VoidCallback onShow;
  final VoidCallback onHide;
  final ValueChanged<SiteRef> onNode;
  final ValueChanged<SiteGo> onGo;
}
