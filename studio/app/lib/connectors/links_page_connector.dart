import 'dart:async';

import 'package:async_redux/async_redux.dart';
import 'package:auto_route/auto_route.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/links/actions/deauthorize_link_action.dart';
import 'package:business/redux/links/actions/hide_links_action.dart';
import 'package:business/redux/links/actions/open_link_update_action.dart';
import 'package:business/redux/links/actions/open_links_row_action.dart';
import 'package:business/redux/links/actions/remove_link_action.dart';
import 'package:business/redux/links/actions/set_tab_action.dart';
import 'package:business/redux/links/actions/show_link_here_action.dart';
import 'package:business/redux/links/actions/show_links_action.dart';
import 'package:business/redux/links/actions/start_link_action.dart';
import 'package:business/redux/links/actions/stop_link_action.dart';
import 'package:business/redux/links/actions/update_all_official_action.dart';
import 'package:business/redux/quarantine/actions/approve_quarantine_action.dart';
import 'package:business/redux/quarantine/actions/reject_quarantine_action.dart';
import 'package:business/redux/quarantine/actions/set_admission_options_action.dart';
import 'package:business/redux/updates/actions/close_update_action.dart';
import 'package:business/redux/updates/actions/rollback_package_action.dart';
import 'package:business/redux/updates/actions/set_accept_new_action.dart';
import 'package:business/redux/updates/actions/set_auto_rollback_action.dart';
import 'package:business/redux/updates/actions/set_take_point_action.dart';
import 'package:business/redux/updates/actions/update_package_action.dart';
import 'package:material_ui/material_ui.dart';
import 'package:models/link_info.dart';
import 'package:ui/models/submit.dart';
import 'package:ui/pages/links_screen.dart';

import '../common/forms.dart';
import '../common/tab_visibility.dart';
import '../common/update_file_action.dart';
import '../dialogs/link_dialogs.dart';
import '../mappers/link_install_mappers.dart';
import '../mappers/links_mappers.dart';
import '../mappers/rights_mappers.dart';
import '../navigation/app_router.dart';
import '../navigation/go_action.dart';

/// Links (docs/studio.md §6.7): the connector reads the selectors of
/// `LinksScreen`, maps the domain through `app/lib/mappers/links_mappers.dart`
/// into typed values (`LinksScreen` words them and asks before what cannot
/// be taken back) and starts one action per intent. A link's dialogs open
/// from the widget, with the widget's context.
@RoutePage()
class LinksPageConnector extends StatelessWidget {
  const LinksPageConnector({super.key});

  @override
  Widget build(BuildContext context) => StoreConnector<AppState, _Vm>(
    debug: this,
    vm: () => _Factory(this),
    builder: (context, vm) => TabVisibility(
      onShow: vm.onShow,
      onHide: vm.onHide,
      child: LinksScreen(
        vm: vm.screen,
        onAdd: vm.onAdd,
        onTab: vm.onTab,
        onRow: vm.onRow,
        onAct: vm.onAct,
        onDialog: (ask) =>
            unawaited(showLinkDialog(context, ask, vm.screen.root)),
        onRemove: vm.onRemove,
        onDeauthorize: vm.onDeauthorize,
        onReject: vm.onReject,
        approve: vm.approve,
        onHoldUnknown: vm.onHoldUnknown,
        onAllowAll: vm.onAllowAll,
        onUpdateAll: vm.onUpdateAll,
        onTakePoint: vm.onTakePoint,
        onAutoRollback: vm.onAutoRollback,
        onAcceptNew: vm.onAcceptNew,
        onUpdate: vm.onUpdate,
        onUpdateFromFile: vm.onUpdateFromFile,
        onRollBack: vm.onRollBack,
        onShowLink: vm.onShowLink,
        onCloseSheet: vm.onCloseSheet,
      ),
    ),
  );
}

/// Factory that creates a view-model for the StoreConnector.
class _Factory extends VmFactory<AppState, LinksPageConnector, _Vm>
    with Selectors {
  _Factory(super._connector);

  /// [l] as its row and inspector draw it.
  LinkData _link(LinkInfo l) {
    final pkg = packageRunBy(l);
    final points = restorePointsOfLink(l.id).length;
    return LinkData(
      id: l.id,
      driver: l.driver,
      mode: l.mode.ui,
      state: stateOfLink(l).ui,
      package: pkg?.data(
        peers: linksOfPackage(pkg.name).length,
        restorePoints: points,
      ),
      device: l.device,
      note: l.note,
      certificateCn: l.certificateCn,
      restorePoints: points,
      reason: linkConfigReason(l.id)?.disabled,
    );
  }

  /// What an action card of the selected link that runs at once starts;
  /// null for the others (they open a dialog or ask first, in
  /// `LinksScreen`, or are done on the device).
  ReduxAction<AppState>? _actionOf(LinkAct a) {
    final id = links.selectedLink;
    if (id == null) {
      return null;
    }
    return switch (a) {
      LinkAct.stop => StopLinkAction(id),
      LinkAct.start => StartLinkAction(id),
      LinkAct.updateTo || LinkAct.updateFromFile => OpenLinkUpdateAction(id),
      LinkAct.versions => OpenLinkUpdateAction(id, follow: true),
      LinkAct.log ||
      LinkAct.params ||
      LinkAct.history ||
      LinkAct.secrets ||
      LinkAct.grant ||
      LinkAct.grants ||
      LinkAct.backup ||
      LinkAct.remove ||
      LinkAct.removeForGood ||
      LinkAct.deauthorize ||
      LinkAct.builtIn ||
      LinkAct.deviceRun ||
      LinkAct.deviceUpgrade => null,
    };
  }

  @override
  _Vm fromStore() {
    final local = localLinks;
    final remote = remoteLinks;
    final waiting = quarantined;
    final tab = links.tab;
    return _Vm(
      screen: LinksScreenVm(
        site: site.viewed ?? '',
        root: site.root ?? '',
        brokerVersion: links.version,
        tab: tab.ui,
        tabs: [
          LinksTabData(LinksTabKey.local, local.length),
          if (showsUpdates) LinksTabData(LinksTabKey.updates, updateCount),
          LinksTabData(LinksTabKey.remote, remote.length),
          LinksTabData(LinksTabKey.quarantine, waiting.length),
        ],
        addReason: linksConfigReason?.disabled,
        updateAll: tab == .updates && updatablePackages.isNotEmpty,
        local: [for (final l in local) _link(l)],
        toUpdate: [for (final l in linksToUpdate) _link(l)],
        remote: [for (final l in remote) _link(l)],
        waiting: [
          for (final q in waiting)
            q.data(
              fields: switch (quarantine.forms[q.node]) {
                final specs? => paramFields(specs),
                null => null,
              },
              reason: quarantineReason(q.node)?.disabled,
            ),
        ],
        loading: links.isWaiting && links.table.isEmpty,
        selectedLink: links.selectedLink,
        selectedEntry: quarantine.selectedEntry,
        updating: updates.package,
        holdUnknown: holdsUnknown,
        allowAll: allowsAllLinks,
        admissionReason: admissionReason?.disabled,
        hasBackups: backups.sections.isNotEmpty,
        busy: links.isActing || quarantine.isWaiting,
        sheet: linkUpdate?.ui,
      ),
      approve: SubmitVm(
        onSubmit: (args) => switch (quarantine.selectedEntry) {
          final node? => sendForm(
            dispatchAndWait(ApproveQuarantineAction(node, plainArgs(args))),
          ),
          null => null,
        },
      ),
      onShow: () => dispatch(ShowLinksAction()),
      onHide: () => dispatch(HideLinksAction()),
      onAdd: () => dispatch(GoAction.push(const LinkInstallRoute())),
      onTab: (t) => dispatch(SetTabAction(t.domain)),
      onRow: (id) => dispatch(OpenLinksRowAction(id)),
      onAct: (a) => switch (_actionOf(a)) {
        final action? => dispatch(action),
        null => null,
      },
      onRemove: (id) => dispatch(RemoveLinkAction(id)),
      onDeauthorize: (id) => dispatch(DeauthorizeLinkAction(id)),
      onReject: (node) => dispatch(RejectQuarantineAction(node)),
      onHoldUnknown: (v) => dispatch(SetAdmissionOptionsAction(holdUnknown: v)),
      onAllowAll: (v) => dispatch(SetAdmissionOptionsAction(allowAll: v)),
      onUpdateAll: () => dispatch(UpdateAllOfficialAction()),
      onTakePoint: (on) => dispatch(SetTakePointAction(on)),
      onAutoRollback: (on) => dispatch(SetAutoRollbackAction(on)),
      onAcceptNew: (on) => dispatch(SetAcceptNewAction(on)),
      onUpdate: () => dispatch(UpdatePackageAction()),
      onUpdateFromFile: () => dispatch(UpdateFromFileAction()),
      onRollBack: (name) => dispatch(RollbackPackageAction(name)),
      onShowLink: (id) => dispatch(ShowLinkHereAction(id)),
      onCloseSheet: () => dispatch(CloseUpdateAction()),
    );
  }
}

/// What Links draws ([screen], compared) and what it starts (not).
class _Vm extends Vm {
  _Vm({
    required this.screen,
    required this.approve,
    required this.onShow,
    required this.onHide,
    required this.onAdd,
    required this.onTab,
    required this.onRow,
    required this.onAct,
    required this.onRemove,
    required this.onDeauthorize,
    required this.onReject,
    required this.onHoldUnknown,
    required this.onAllowAll,
    required this.onUpdateAll,
    required this.onTakePoint,
    required this.onAutoRollback,
    required this.onAcceptNew,
    required this.onUpdate,
    required this.onUpdateFromFile,
    required this.onRollBack,
    required this.onShowLink,
    required this.onCloseSheet,
  }) : super(equals: [screen, approve]);

  final LinksScreenVm screen;
  final SubmitVm approve;
  final VoidCallback onShow;
  final VoidCallback onHide;
  final VoidCallback onAdd;
  final ValueChanged<LinksTabKey> onTab;
  final ValueChanged<String> onRow;
  final ValueChanged<LinkAct> onAct;
  final ValueChanged<String> onRemove;
  final ValueChanged<String> onDeauthorize;
  final ValueChanged<String> onReject;
  final ValueChanged<bool> onHoldUnknown;
  final ValueChanged<bool> onAllowAll;
  final VoidCallback onUpdateAll;
  final ValueChanged<bool> onTakePoint;
  final ValueChanged<bool> onAutoRollback;
  final ValueChanged<bool> onAcceptNew;
  final VoidCallback onUpdate;
  final VoidCallback onUpdateFromFile;
  final ValueChanged<String> onRollBack;
  final ValueChanged<String> onShowLink;
  final VoidCallback onCloseSheet;
}
