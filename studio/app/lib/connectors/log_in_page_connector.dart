import 'package:async_redux/async_redux.dart';
import 'package:auto_route/auto_route.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/clock/actions/tick_clock_action.dart';
import 'package:business/redux/device/actions/accept_offer_action.dart';
import 'package:business/redux/device/actions/decline_offer_action.dart';
import 'package:business/redux/device/actions/forget_account_action.dart';
import 'package:business/redux/device/actions/set_re_enable_action.dart';
import 'package:business/redux/device/actions/unlock_with_device_action.dart';
import 'package:business/redux/device/actions/use_password_action.dart';
import 'package:business/redux/discovery/actions/choose_found_gateway_action.dart';
import 'package:business/redux/discovery/actions/confirm_trust_action.dart';
import 'package:business/redux/discovery/actions/find_gateways_action.dart';
import 'package:business/redux/discovery/actions/probe_typed_range_action.dart';
import 'package:business/redux/discovery/actions/set_range_action.dart';
import 'package:business/redux/discovery/actions/set_range_port_action.dart';
import 'package:business/redux/discovery/actions/set_trust_pending_action.dart';
import 'package:business/redux/discovery/actions/toggle_discovery_action.dart';
import 'package:business/redux/login/actions/open_log_in_action.dart';
import 'package:business/redux/login/actions/pick_recent_gateway_action.dart';
import 'package:business/redux/login/actions/probe_gateway_action.dart';
import 'package:business/redux/login/actions/set_main_gateway_action.dart';
import 'package:business/redux/login/actions/set_password_action.dart';
import 'package:business/redux/login/actions/set_remember_action.dart';
import 'package:business/redux/login/actions/set_standby_gateway_action.dart';
import 'package:business/redux/login/actions/set_user_action.dart';
import 'package:business/redux/login/actions/sign_in_action.dart';
import 'package:business/redux/login/actions/use_standby_action.dart';
import 'package:business/wyrm/device_keys.dart';
import 'package:material_ui/material_ui.dart';
import 'package:models/host_platform.dart';
import 'package:ui/models/value_changed.dart';
import 'package:ui/pages/log_in_data.dart';
import 'package:ui/pages/log_in_screen.dart';

import '../common/every.dart';
import '../common/studio_version.dart';
import '../common/validators.dart';
import '../common/window.dart';
import '../mappers/device_mappers.dart';
import '../mappers/log_in_mappers.dart';
import '../navigation/enter_studio_action.dart';
import '../navigation/open_network_settings_action.dart';

/// The log-in page (docs/design/specs/login.md, unlock-discover.md): it
/// reads selectors, maps the domain through `app/lib/mappers/`, passes
/// typed values (`LogInScreen` words them) and starts one action per
/// intent. A log-in, an unlock and an answer to the offer leave for
/// Studio through `EnterStudioAction`.
@RoutePage()
class LogInPageConnector extends StatelessWidget {
  const LogInPageConnector({super.key});

  @override
  Widget build(BuildContext context) => StoreConnector<AppState, _Vm>(
    debug: this,
    vm: () => _Factory(this),
    // §6: the gateway in the field is probed as the page opens, and the
    // device unlock of its user is read (unlock-discover.md §2).
    onInit: (store) => store.dispatch(OpenLogInAction()),
    // A found gateway's `seen 3 s ago` moves on once a second while the
    // search is open (`clock.now`).
    builder: (context, vm) => Every(
      period: const Duration(seconds: 1),
      enabled: vm.screen.discover != null,
      onTick: vm.onTick,
      child: LogInScreen(
        vm: vm.screen,
        onLogIn: vm.onLogIn,
        onGatewayLeave: vm.onGatewayLeave,
        onRecent: vm.onRecent,
        onUseStandby: vm.onUseStandby,
        onFind: vm.onFind,
        onLookAgain: vm.onLookAgain,
        onPick: vm.onPick,
        onProbe: vm.onProbe,
        onOpenSettings: vm.onOpenSettings,
        onTrust: vm.onTrust,
        onCancelTrust: vm.onCancelTrust,
        onOfferUse: vm.onOfferUse,
        onOfferNotNow: vm.onOfferNotNow,
        onOfferDontAsk: vm.onOfferDontAsk,
        onUnlock: vm.onUnlock,
        onAutoUnlock: vm.onAutoUnlock,
        onUsePassword: vm.onUsePassword,
        onAnotherAccount: vm.onAnotherAccount,
      ),
    ),
  );
}

/// Factory that creates a view-model for the StoreConnector.
class _Factory extends VmFactory<AppState, LogInPageConnector, _Vm>
    with Selectors {
  _Factory(super._connector);

  @override
  _Vm fromStore() {
    final busy = login.isWaiting;
    final field = login.field;
    final standby = field.standbyUri;
    final platform = hostPlatform();
    return _Vm(
      screen: LogInScreenVm(
        window: windowBar(fullScreen: window.fullScreen),
        gateway: FieldVm(
          value: field.main,
          validator: gatewayValidator,
          onChanged: (v) => dispatchSync(SetMainGatewayAction(v)),
          enabled: !busy,
        ),
        standby: FieldVm(
          value: field.standby,
          onChanged: (v) => dispatchSync(SetStandbyGatewayAction(v)),
          enabled: !busy,
        ),
        user: FieldVm(
          value: login.user,
          validator: requiredValidator.call,
          onChanged: (v) => dispatchSync(SetUserAction(v)),
          enabled: !busy,
        ),
        // A gateway password has no shape rules here: the administrator who
        // made the user chose it, and the gateway is the one that checks it.
        password: FieldVm(
          value: login.password,
          validator: requiredValidator.call,
          onChanged: (v) => dispatchSync(SetPasswordAction(v)),
          enabled: !busy,
        ),
        remember: FieldVm(
          value: login.remember,
          onChanged: (v) => dispatchSync(SetRememberAction(v)),
          enabled: !busy,
        ),
        reEnable: FieldVm(
          value: device.reEnable,
          onChanged: (v) => dispatchSync(SetReEnableAction(v)),
          enabled: !busy,
        ),
        version: studioVersion,
        busy: busy,
        reach: login.fieldState.tone,
        note: login.fieldNote?.note,
        checking: login.isProbing,
        recent: [for (final r in login.recentGateways) r.chip],
        fieldLabel: login.fieldLabel,
        step: login.step,
        wrong: login.failure == .wrong,
        unreachable: login.failure == .unreachable
            ? UnreachableData(
                gateway: field.main,
                reason: login.reason,
                standby: field.standbyHost,
              )
            : null,
        tls: login.tlsLine?.note,
        standbyHost: field.standbyHost,
        welcome: session.isAvailable && device.stage != .offer
            ? WelcomeData(
                user: site.userName,
                site: site.name ?? '',
                otherSites: site.otherSites,
                role: site.role,
                links: nodes.linkCount,
                step: login.preload,
                late: login.preloadLate.toSet(),
              )
            : null,
        offer: session.isAvailable && device.stage == .offer
            ? OfferData(
                method: device.kind.method,
                os: platform.os,
                biometric: device.available,
                site: device.offerSite,
                user: site.userName,
                role: site.role ?? '',
                maxPerUser: device.maxPerUser,
                passwordEveryDays: device.passwordEveryDays,
                standbyHost: standby?.host,
                busy: device.isEnabling,
              )
            : null,
        unlock: switch (device.stage.form) {
          final form? when !session.isAvailable => unlockData(form, platform),
          _ => null,
        },
        discover: discovery.open && discovery.pendingRow == null
            ? _discover(platform)
            : null,
        trust: switch (discovery.pendingRow) {
          final row? => TrustData(
            site: row.site,
            code: discovery.pendingCode,
            host: discovery.pendingHost,
            refused: discovery.trustRefused?.refused,
            busy: discovery.isWaiting,
          ),
          null => null,
        },
      ),
      onLogIn: () => dispatch(EnterStudioAction(SignInAction())),
      onGatewayLeave: () => dispatch(ProbeGatewayAction()),
      onRecent: (r) => dispatch(PickRecentGatewayAction(r)),
      onUseStandby: standby == null
          ? null
          : () => dispatch(EnterStudioAction(UseStandbyAction())),
      onFind: busy ? null : () => dispatch(ToggleDiscoveryAction()),
      onLookAgain: () => dispatch(FindGatewaysAction()),
      onPick: (site) => dispatch(ChooseFoundGatewayAction(site)),
      onProbe: () => dispatch(ProbeTypedRangeAction()),
      onOpenSettings: OpenNetworkSettingsAction.pageOf(platform) == null
          ? null
          : () => dispatch(OpenNetworkSettingsAction()),
      onTrust: discovery.trustPending == null
          ? null
          : () => dispatch(ConfirmTrustAction()),
      onCancelTrust: () => dispatchSync(SetTrustPendingAction(null)),
      onOfferUse: () => dispatch(EnterStudioAction(AcceptOfferAction())),
      onOfferNotNow: () => dispatch(EnterStudioAction(DeclineOfferAction())),
      onOfferDontAsk: () =>
          dispatch(EnterStudioAction(DeclineOfferAction(dontAsk: true))),
      onUnlock: login.keyReady
          ? () => dispatch(EnterStudioAction(UnlockWithDeviceAction()))
          : null,
      onAutoUnlock: login.keyReady
          ? () =>
                dispatch(EnterStudioAction(UnlockWithDeviceAction(auto: true)))
          : null,
      onUsePassword: () => dispatchSync(UsePasswordAction()),
      onAnotherAccount: () => dispatchSync(ForgetAccountAction()),
      onTick: () => dispatchSync(TickClockAction()),
    );
  }

  /// *Find on this network* (unlock-discover.md §4).
  DiscoverData _discover(HostPlatform platform) => DiscoverData(
    rows: [for (final r in discovery.rowsAt(clock.now)) r.line],
    scanning: discovery.scanning,
    probing: discovery.probing,
    ended: discovery.ended,
    network: discovery.network,
    subnet: discovery.subnet,
    range: FieldVm(
      value: discovery.rangeText,
      onChanged: (v) => dispatchSync(SetRangeAction(v)),
    ),
    port: FieldVm(
      value: discovery.portText,
      onChanged: (v) => dispatchSync(SetRangePortAction(v)),
    ),
    rangeProblem: discovery.rangeFault?.problem,
    portBad: discovery.probePort == null,
    permission: platform.permission,
    settings: OpenNetworkSettingsAction.pageOf(platform) != null,
  );
}

/// What the page draws ([screen], compared), whether its optional controls
/// react (compared), and what it starts (not).
class _Vm extends Vm {
  _Vm({
    required this.screen,
    required this.onLogIn,
    required this.onGatewayLeave,
    required this.onRecent,
    required this.onUseStandby,
    required this.onFind,
    required this.onLookAgain,
    required this.onPick,
    required this.onProbe,
    required this.onOpenSettings,
    required this.onTrust,
    required this.onCancelTrust,
    required this.onOfferUse,
    required this.onOfferNotNow,
    required this.onOfferDontAsk,
    required this.onUnlock,
    required this.onAutoUnlock,
    required this.onUsePassword,
    required this.onAnotherAccount,
    required this.onTick,
  }) : super(
         equals: [
           screen,
           onUseStandby != null,
           onFind != null,
           onOpenSettings != null,
           onTrust != null,
           onUnlock != null,
           onAutoUnlock != null,
         ],
       );

  final LogInScreenVm screen;
  final VoidCallback onLogIn;
  final VoidCallback onGatewayLeave;
  final ValueChanged<String> onRecent;
  final VoidCallback? onUseStandby;
  final VoidCallback? onFind;
  final VoidCallback onLookAgain;
  final ValueChanged<String> onPick;
  final VoidCallback onProbe;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onTrust;
  final VoidCallback onCancelTrust;
  final VoidCallback onOfferUse;
  final VoidCallback onOfferNotNow;
  final VoidCallback onOfferDontAsk;
  final VoidCallback? onUnlock;
  final VoidCallback? onAutoUnlock;
  final VoidCallback onUsePassword;
  final VoidCallback onAnotherAccount;
  final VoidCallback onTick;
}
