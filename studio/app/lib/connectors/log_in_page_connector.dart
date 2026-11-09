import 'dart:async';

import 'package:async_redux/async_redux.dart';
import 'package:auto_route/auto_route.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/login/actions/log_in_action.dart';
import 'package:business/redux/login/actions/open_tree_action.dart';
import 'package:business/redux/login/actions/probe_gateway_action.dart';
import 'package:business/redux/login/actions/set_gateway_action.dart';
import 'package:business/redux/login/actions/set_password_action.dart';
import 'package:business/redux/login/actions/set_remember_action.dart';
import 'package:business/redux/login/actions/set_user_action.dart';
import 'package:business/wyrm/session.dart';
import 'package:flutter/material.dart';
import 'package:localization/localization.dart';
import 'package:models/login_failure.dart';
import 'package:ui/alerts/unreachable_alert.dart';
import 'package:ui/buttons/recent_chip.dart';
import 'package:ui/containers/welcome_panel.dart';
import 'package:ui/models/tone.dart';
import 'package:ui/models/value_changed.dart';
import 'package:ui/pages/log_in_page.dart';
import 'package:ui/shell/window_bar.dart';

import '../common/validators.dart';
import '../common/window.dart';
import '../navigation/app_router.dart';
import '../navigation/go_action.dart';

@RoutePage()
class LogInPageConnector extends StatelessWidget {
  const LogInPageConnector({super.key});

  @override
  Widget build(BuildContext context) => StoreConnector<AppState, _Vm>(
    debug: this,
    vm: () => _Factory(this),
    // §6: the gateway in the field is probed as the page opens.
    onInit: (store) => unawaited(store.dispatchAndWait(ProbeGatewayAction())),
    builder: (context, vm) => LogInPage(
      window: vm.window,
      gateway: vm.gateway,
      user: vm.user,
      password: vm.password,
      isWaiting: vm.isWaiting,
      onPressedLogIn: vm.onPressedLogIn,
      version: vm.version,
      standby: vm.standby,
      gatewayTone: vm.gatewayTone,
      gatewayNote: vm.gatewayNote,
      checking: vm.checking,
      onGatewayLeave: vm.onGatewayLeave,
      recent: vm.recent,
      onRecent: vm.onRecent,
      remember: vm.remember,
      steps: vm.steps,
      step: vm.step,
      wrong: vm.wrong,
      unreachable: vm.unreachable,
      onRetry: vm.onPressedLogIn,
      onUseStandby: vm.onUseStandby,
      tls: vm.tls,
      standbyLabel: vm.standbyLabel,
      welcome: vm.welcome,
    ),
  );
}

/// The gateway of the demo's central site (examples/demo/run.sh).
const defaultGateway = 'http://127.0.0.1:8445';

/// The version in the log-in footer (`app/pubspec.yaml`).
const studioVersion = '1.0';

/// A gateway's short name, as the board writes it: the first label of a host
/// name (`plant.local` → `plant`), an address whole (`127.0.0.1`).
String shortHost(Uri uri) {
  final host = uri.host;
  final address = RegExp(r'^[\d.]+$').hasMatch(host) || host.contains(':');
  return address ? host : host.split('.').first;
}

/// `user:olena@plant` → `olena`.
String _userName(String subject) {
  final name = subject.startsWith('user:') ? subject.substring(5) : subject;
  final at = name.indexOf('@');
  return at < 0 ? name : name.substring(0, at);
}

/// `a`, `a and b`, `a, b and c`.
String _list(List<String> items) => switch (items) {
  [] => '',
  [final one] => one,
  [...final head, final last] => S.current.listAnd(head.join(', '), last),
};

/// Factory that creates a view-model for the StoreConnector.
class _Factory extends VmFactory<AppState, LogInPageConnector, _Vm>
    with Selectors {
  _Factory(super._connector);

  @override
  _Vm fromStore() {
    // The field holds one URL, or a main and a standby separated by a comma
    // (ADR 0036): the page shows them as two fields.
    final text = login.gateway ?? defaultGateway;
    final parts = text.split(',').map((p) => p.trim()).toList();
    final main = parts.first;
    final standby = parts.length > 1 && parts[1].isNotEmpty ? parts[1] : null;
    String join(String? a, String? b) => [
      if (a != null && a.isNotEmpty) a,
      if (b != null && b.isNotEmpty) b,
    ].join(', ');

    final uri = parseGateways(main).firstOrNull;
    final short = uri == null ? main : shortHost(uri);
    final failure = login.failure;
    final ms = uri == null ? null : login.probes[gatewayKey(uri)];
    final down = failure == LoginFailure.unreachable || ms == -1;
    final standbyUri = standby == null
        ? null
        : parseGateways(standby).firstOrNull;
    final busy = login.isWaiting;

    Future<void> logIn() async {
      // The default shown in the field is only a hint until it is written.
      if (login.gateway == null) {
        dispatchSync(SetGatewayAction(defaultGateway));
      }
      final status = await dispatchAndWait(LogInAction());
      if (!status.isCompletedOk) {
        return;
      }
      // The welcome stays until the first list of the tree has arrived.
      await dispatchAndWait(OpenTreeAction());
      // The auth guard is re-run by the token's listenable, but auto_route
      // 11 does not redirect away from a resolved route on it: go there.
      dispatch(GoAction.replace(const StudioRoute()));
    }

    return _Vm(
      window: windowBar(fullScreen: window.fullScreen),
      gateway: FieldVm(
        value: main,
        validator: gatewayValidator,
        onChanged: (v) => dispatchSync(SetGatewayAction(join(v, standby))),
        enabled: !busy,
      ),
      standby: FieldVm(
        value: standby,
        onChanged: (v) => dispatchSync(SetGatewayAction(join(main, v))),
        enabled: !busy,
      ),
      user: FieldVm(
        value: login.user,
        validator: (v) => requiredValidator(v),
        onChanged: (v) => dispatchSync(SetUserAction(v)),
        enabled: !busy,
      ),
      // A gateway password has no shape rules here: the administrator who made
      // the user chose it, and the gateway is the one that checks it.
      password: FieldVm(
        value: login.password,
        validator: (v) => requiredValidator(v),
        onChanged: (v) => dispatchSync(SetPasswordAction(v)),
        error: failure == LoginFailure.wrong ? S.current.wrongPassword : null,
        enabled: !busy,
      ),
      isWaiting: busy,
      onPressedLogIn: () => unawaited(logIn()),
      // The board shows the language in use, not a switcher (owner decision
      // 2026-11-08, docs/design/specs/login.md §3.8).
      version: S.current.studioVersion(studioVersion, S.current.languageName),
      gatewayTone: down
          ? Tone.bad
          : ms == null
          ? Tone.neutral
          : Tone.good,
      gatewayNote: down
          ? S.current.gatewayNoAnswer(short)
          : ms == null
          ? null
          : S.current.gatewayAnswered(short, ms),
      checking: login.isProbing,
      onGatewayLeave: () => unawaited(dispatchAndWait(ProbeGatewayAction())),
      recent: [
        for (final r in login.recent)
          if (parseGateways(r).firstOrNull case final u?)
            RecentChipVm(
              id: r,
              label: shortHost(u),
              tone: switch (login.probes[gatewayKey(u)]) {
                null => Tone.neutral,
                -1 => Tone.bad,
                _ => Tone.good,
              },
              current: r == text.trim(),
            ),
      ],
      onRecent: (r) {
        dispatchSync(SetGatewayAction(r));
        unawaited(dispatchAndWait(ProbeGatewayAction(r)));
      },
      remember: FieldVm(
        value: login.remember,
        onChanged: (v) => dispatchSync(SetRememberAction(v)),
        enabled: !busy,
      ),
      steps: [
        S.current.stepReaching(short),
        S.current.stepChecking,
        S.current.stepReading,
      ],
      step: login.step,
      wrong: failure == LoginFailure.wrong,
      unreachable: failure == LoginFailure.unreachable
          ? UnreachableAlertVm(
              detail: [main, ?login.reason].join(' · '),
              advice: S.current.unreachableAdvice,
              standby: standbyUri == null
                  ? null
                  : '${standbyUri.host}:${standbyUri.port}',
            )
          : null,
      onUseStandby: standby == null
          ? null
          : () {
              dispatchSync(SetGatewayAction(join(standby, main)));
              unawaited(logIn());
            },
      tls: uri?.scheme == 'https'
          ? S.current.tlsCertificateOf(
              site.gateway != null &&
                      parseGateways(site.gateway!).firstOrNull?.origin ==
                          uri!.origin &&
                      site.name != null
                  ? site.name!
                  : short,
            )
          : null,
      standbyLabel: standbyUri == null
          ? null
          : S.current.standbyIs('${standbyUri.host}:${standbyUri.port}'),
      welcome: session.isAvailable ? _welcome() : null,
    );
  }

  /// What is known while the tree opens: who and where from `me()`, the
  /// sites from the switcher's list, the links from the first list, and the
  /// steps of the preload (docs/design/specs/login.md §5).
  WelcomePanelVm _welcome() {
    final name = site.name ?? '';
    final others = [
      for (final c in site.choices)
        if (c.site != name) c.site,
    ];
    final role = site.role;
    final prefix = '${site.root}/downstream/';
    final links = nodes.table.keys
        .where((k) => k.startsWith(prefix))
        .where((k) => !k.substring(prefix.length).contains('/'))
        .length;
    final late = login.preloadLate.toSet();
    return WelcomePanelVm(
      title: S.current.welcomeUser(_userName(site.user ?? login.user ?? '')),
      site: name,
      // The preload of OpenTreeAction, one line a step; a late one says it
      // goes on after Studio opens.
      steps: [
        for (final (i, label) in [
          S.current.preloadTree(name),
          S.current.preloadFlows,
          S.current.preloadBlocks,
          S.current.preloadLinks,
          S.current.preloadSites,
        ].indexed)
          if (late.contains(i)) S.current.preloadLater(label) else label,
      ],
      step: login.preload,
      late: late,
      facts: [
        if (role != null && role.isNotEmpty)
          [
            S.current.roleOnSite(role, name),
            if (others.isNotEmpty) S.current.reachesSites(_list(others)),
          ].join(' · '),
        if (links > 0) S.current.linksCount(links),
      ],
    );
  }
}

/// The view-model holds the part of the Store state the dumb-widget needs.
class _Vm extends Vm {
  _Vm({
    required this.window,
    required this.gateway,
    required this.standby,
    required this.user,
    required this.password,
    required this.isWaiting,
    required this.onPressedLogIn,
    required this.version,
    required this.gatewayTone,
    required this.gatewayNote,
    required this.checking,
    required this.onGatewayLeave,
    required this.recent,
    required this.onRecent,
    required this.remember,
    required this.steps,
    required this.step,
    required this.wrong,
    required this.unreachable,
    required this.onUseStandby,
    required this.tls,
    required this.standbyLabel,
    required this.welcome,
  }) : super(
         equals: [
           window,
           gateway,
           standby,
           user,
           password,
           isWaiting,
           version,
           gatewayTone,
           gatewayNote,
           checking,
           recent,
           remember,
           steps,
           step,
           wrong,
           unreachable,
           onUseStandby != null,
           tls,
           standbyLabel,
           welcome,
         ],
       );

  /// The frameless window's side of the top bar.
  final WindowBarVm window;

  final FieldVm<String?> gateway;
  final FieldVm<String?> standby;
  final FieldVm<String?> user;
  final FieldVm<String?> password;
  final bool isWaiting;
  final VoidCallback onPressedLogIn;
  final String version;
  final Tone gatewayTone;
  final String? gatewayNote;
  final bool checking;
  final VoidCallback onGatewayLeave;
  final List<RecentChipVm> recent;
  final ValueChanged<String> onRecent;
  final FieldVm<bool> remember;
  final List<String> steps;
  final int step;
  final bool wrong;
  final UnreachableAlertVm? unreachable;
  final VoidCallback? onUseStandby;
  final String? tls;
  final String? standbyLabel;
  final WelcomePanelVm? welcome;
}
