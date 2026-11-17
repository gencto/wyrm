import 'dart:async';

import 'package:async_redux/async_redux.dart';
import 'package:auto_route/auto_route.dart';
import 'package:business/redux/access/actions/pick_user_action.dart';
import 'package:business/redux/access/actions/poll_access_action.dart';
import 'package:business/redux/access/actions/set_shown_action.dart';
import 'package:business/redux/access/actions/set_tab_action.dart';
import 'package:business/redux/access/actions/show_access_action.dart';
import 'package:business/redux/app_state.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/pages/access_page.dart';
import 'package:wyrm_client/wyrm_client.dart' show Perm;

import '../common/every.dart';
import '../common/tab_visibility.dart';
import '../dialogs/access_dialogs.dart';
import '../mappers/access_mappers.dart';
import '../mappers/rights_mappers.dart';

/// Access: the gateway's users, the grants and the audit tail, mapped
/// through `app/lib/mappers/access_mappers.dart`; `AccessPage` words them.
/// One action per intent; its forms and confirmations open from the
/// widget, with the widget's context (`app/lib/dialogs/access_dialogs.dart`).
@RoutePage()
class AccessPageConnector extends StatelessWidget {
  const AccessPageConnector({super.key});

  @override
  Widget build(BuildContext context) => StoreConnector<AppState, _Vm>(
    debug: this,
    vm: () => _Factory(this),
    builder: (context, vm) => TabVisibility(
      onShow: vm.onShow,
      onHide: vm.onHide,
      // `/api/users` has no stream: read again every 10 s while shown.
      child: Every(
        period: const Duration(seconds: 10),
        enabled: vm.polling,
        onTick: vm.onPoll,
        child: AccessPage(
          vm: vm.page,
          onTab: vm.onTab,
          onUser: vm.onUser,
          onAddUser: () => unawaited(addUser(context)),
          onAddGrant: () => unawaited(addGrant(context)),
          onPick: (pick) => unawaited(changeUser(context, pick)),
        ),
      ),
    ),
  );
}

/// Factory that creates a view-model for the StoreConnector.
class _Factory extends VmFactory<AppState, AccessPageConnector, _Vm>
    with Selectors {
  _Factory(super._connector);

  @override
  _Vm fromStore() {
    final sys = '${site.home}/sys';
    final u = access.pickedUser;
    return _Vm(
      page: AccessVm(
        site: site.name ?? '',
        tab: access.tab.view,
        users: [for (final x in access.users) x.row],
        grants: [for (final g in access.grants) g.row],
        audit: [for (final l in access.audit) l.row],
        picked: u == null
            ? null
            : PickedUserVm(
                user: u.row,
                grants: [for (final g in access.grantsOf(u)) g.row],
                devices: [
                  for (final r in device.userRowsAt(u.name, clock.now))
                    r.accessRow,
                ],
              ),
        usersLocked: site.lacks(Perm.config, sys) != null,
        grantsDisabled: site.lacks(Perm.config, sys)?.disabled,
      ),
      polling: access.shown,
      onShow: () => dispatch(ShowAccessAction()),
      onHide: () => dispatchSync(SetShownAction(false)),
      onPoll: () => dispatch(PollAccessAction()),
      onTab: (t) => dispatchSync(SetTabAction(t.tab)),
      onUser: (name) => dispatch(PickUserAction(name)),
    );
  }
}

/// What Access draws ([page] and [polling], compared) and what it starts
/// (not).
class _Vm extends Vm {
  _Vm({
    required this.page,
    required this.polling,
    required this.onShow,
    required this.onHide,
    required this.onPoll,
    required this.onTab,
    required this.onUser,
  }) : super(equals: [page, polling]);

  final AccessVm page;

  /// The tab is shown: Access reads again every 10 s.
  final bool polling;
  final VoidCallback onShow;
  final VoidCallback onHide;
  final VoidCallback onPoll;
  final ValueChanged<AccessView> onTab;
  final ValueChanged<String> onUser;
}
