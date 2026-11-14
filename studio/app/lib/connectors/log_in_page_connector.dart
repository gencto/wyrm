import 'dart:async';

import 'package:async_redux/async_redux.dart';
import 'package:auto_route/auto_route.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/device/actions/decline_offer_action.dart';
import 'package:business/redux/device/actions/enable_device_action.dart';
import 'package:business/redux/device/actions/forget_account_action.dart';
import 'package:business/redux/device/actions/load_device_action.dart';
import 'package:business/redux/device/actions/offer_device_action.dart';
import 'package:business/redux/device/actions/set_re_enable_action.dart';
import 'package:business/redux/device/actions/unlock_with_device_action.dart';
import 'package:business/redux/device/actions/use_password_action.dart';
import 'package:business/redux/discovery/actions/close_discovery_action.dart';
import 'package:business/redux/discovery/actions/find_gateways_action.dart';
import 'package:business/redux/discovery/actions/pick_found_gateway_action.dart';
import 'package:business/redux/discovery/actions/probe_range_action.dart';
import 'package:business/redux/discovery/actions/set_range_action.dart';
import 'package:business/redux/discovery/actions/set_range_port_action.dart';
import 'package:business/redux/discovery/actions/set_trust_pending_action.dart';
import 'package:business/redux/discovery/actions/trust_gateway_action.dart';
import 'package:business/redux/login/actions/log_in_action.dart';
import 'package:business/redux/login/actions/open_tree_action.dart';
import 'package:business/redux/login/actions/probe_gateway_action.dart';
import 'package:business/redux/login/actions/set_gateway_action.dart';
import 'package:business/redux/login/actions/set_password_action.dart';
import 'package:business/redux/login/actions/set_remember_action.dart';
import 'package:business/redux/login/actions/set_user_action.dart';
import 'package:business/wyrm/device_keys.dart';
import 'package:business/wyrm/discovery.dart';
import 'package:business/wyrm/session.dart';
import 'package:flutter/foundation.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:models/found_gateway.dart';
import 'package:models/found_problem.dart';
import 'package:models/login_failure.dart';
import 'package:models/unlock_refusal.dart';
import 'package:models/unlock_stage.dart';
import 'package:ui/alerts/trust_card.dart';
import 'package:ui/alerts/unlock_notice.dart';
import 'package:ui/alerts/unreachable_alert.dart';
import 'package:ui/buttons/found_gateway_row.dart';
import 'package:ui/buttons/recent_chip.dart';
import 'package:ui/containers/discover_panel.dart';
import 'package:ui/containers/unlock_offer.dart';
import 'package:ui/containers/unlock_panel.dart';
import 'package:ui/containers/welcome_panel.dart';
import 'package:ui/indicators/biometric_icon.dart';
import 'package:ui/models/tone.dart';
import 'package:ui/models/value_changed.dart';
import 'package:ui/pages/log_in_page.dart';
import 'package:ui/shell/window_bar.dart';
import 'package:url_launcher/url_launcher.dart';

import '../common/unlock.dart';
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
    // §6: the gateway in the field is probed as the page opens, and the
    // device unlock of its user is read (unlock-discover.md §2).
    onInit: (store) {
      unawaited(store.dispatchAndWait(ProbeGatewayAction()));
      unawaited(store.dispatchAndWait(LoadDeviceAction()));
    },
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
      gatewayHint: 'https://host:port',
      onFind: vm.onFind,
      discover: vm.discover,
      onLookAgain: vm.onLookAgain,
      onPick: vm.onPick,
      onProbe: vm.onProbe,
      onOpenSettings: vm.onOpenSettings,
      trust: vm.trust,
      onTrust: vm.onTrust,
      onCancelTrust: vm.onCancelTrust,
      tlsTone: vm.tlsTone,
      offer: vm.offer,
      onOfferUse: vm.onOfferUse,
      onOfferNotNow: vm.onOfferNotNow,
      onOfferDontAsk: vm.onOfferDontAsk,
      unlock: vm.unlock,
      reEnable: vm.reEnable,
      onUnlock: vm.onUnlock,
      onAutoUnlock: vm.onAutoUnlock,
      onUsePassword: vm.onUsePassword,
      onAnotherAccount: vm.onAnotherAccount,
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
    final pending = discovery.trustPending;
    final pendingRow = pending == null ? null : discovery.found[pending];
    final picked = switch (discovery.picked) {
      final p? => discovery.found[p],
      null => null,
    };
    // The status line names a picked row while the field still holds it.
    final pickedNote =
        picked != null &&
            picked.url != null &&
            parseGateways(picked.url!).firstOrNull?.origin == uri?.origin
        ? picked.standby == null
              ? S.current.pickedFrom(picked.site)
              : S.current.pickedWithStandby(picked.site)
        : null;
    final pin = uri == null ? null : discovery.pins[uri.origin];

    Future<void> open() async {
      // The welcome stays until the first list of the tree has arrived.
      await dispatchAndWait(OpenTreeAction());
      // The auth guard is re-run by the token's listenable, but auto_route
      // 11 does not redirect away from a resolved route on it: go there.
      dispatchSync(GoAction.replace(const StudioRoute()));
    }

    final who = (login.user ?? '').trim();
    final keySite = device.keySite ?? short;
    Future<void> enable() => dispatchAndWait(
      EnableDeviceAction(
        reason: S.current.unlockEnablePrompt(site.name ?? keySite, who),
      ),
    );

    Future<void> logIn() async {
      // The default shown in the field is only a hint until it is written.
      if (login.gateway == null) {
        dispatchSync(SetGatewayAction(defaultGateway));
      }
      final status = await dispatchAndWait(LogInAction());
      if (!status.isCompletedOk) {
        return;
      }
      // Before Welcome: the offer, or a key made again (spec §2).
      await dispatchAndWait(OfferDeviceAction(enable: enable));
      if (currentState().device.stage == UnlockStage.offer) {
        return;
      }
      await open();
    }

    Future<void> unlock({bool auto = false}) async {
      final status = await dispatchAndWait(
        UnlockWithDeviceAction(
          reason: S.current.unlockPrompt(keySite, who),
          auto: auto,
        ),
      );
      if (status.isCompletedOk && currentState().session.token != null) {
        await open();
      }
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
      gatewayTone: pendingRow != null
          ? Tone.warn
          : down
          ? Tone.bad
          : ms == null
          ? Tone.neutral
          : Tone.good,
      gatewayNote: pickedNote != null && !down
          ? pickedNote
          : down
          ? S.current.gatewayNoAnswer(short)
          : ms == null
          ? (main.isEmpty ? S.current.typeOrFind : null)
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
        unawaited(dispatchAndWait(LoadDeviceAction()));
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
      tls: pendingRow != null
          ? S.current.tlsNotTrusted(pendingRow.site)
          : pin != null
          ? S.current.tlsPinned(pin.site.isEmpty ? short : pin.site)
          : uri?.scheme == 'https'
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
      welcome: session.isAvailable && device.stage != UnlockStage.offer
          ? _welcome()
          : null,
      offer: session.isAvailable && device.stage == UnlockStage.offer
          ? _offer(standbyUri)
          : null,
      onOfferUse: () => unawaited(() async {
        if (currentState().device.available) {
          await enable();
        } else {
          await dispatchAndWait(DeclineOfferAction());
        }
        await open();
      }()),
      onOfferNotNow: () => unawaited(() async {
        await dispatchAndWait(DeclineOfferAction());
        await open();
      }()),
      onOfferDontAsk: () => unawaited(() async {
        await dispatchAndWait(DeclineOfferAction(dontAsk: true));
        await open();
      }()),
      unlock: session.isAvailable
          ? null
          : _unlock(
              main: main,
              standby: standbyUri,
              down: down,
              tls: uri?.scheme == 'https'
                  ? S.current.tlsCertificateOf(keySite)
                  : '',
            ),
      reEnable: FieldVm(
        value: device.reEnable,
        onChanged: (v) => dispatchSync(SetReEnableAction(v)),
        enabled: !busy,
      ),
      onUnlock: down || device.keyId == null ? null : () => unawaited(unlock()),
      onAutoUnlock: down || device.keyId == null
          ? null
          : () => unawaited(unlock(auto: true)),
      onUsePassword: () => dispatchSync(UsePasswordAction()),
      onAnotherAccount: () => dispatchSync(ForgetAccountAction()),
      onFind: busy
          ? null
          : () => discovery.open
                ? dispatchSync(CloseDiscoveryAction())
                : unawaited(dispatchAndWait(FindGatewaysAction())),
      discover: discovery.open && pendingRow == null ? _discover() : null,
      onLookAgain: () => unawaited(dispatchAndWait(FindGatewaysAction())),
      onPick: (site) async {
        final status = await dispatchAndWait(PickFoundGatewayAction(site));
        if (status.isCompletedOk && discovery.trustPending == null) {
          await dispatchAndWait(ProbeGatewayAction());
        }
      },
      onProbe: () {
        final (range, port) = _rangeAndPort();
        if (_rangeError(range) == null && _portError(port) == null) {
          unawaited(
            dispatchAndWait(ProbeRangeAction(range, int.parse(port))),
          );
        }
      },
      onOpenSettings: _settings,
      trust: pendingRow == null ? null : _trust(pendingRow),
      onTrust: pending == null
          ? null
          : () async {
              final status = await dispatchAndWait(TrustGatewayAction(pending));
              if (status.isCompletedOk && discovery.trustPending == null) {
                await dispatchAndWait(ProbeGatewayAction());
              }
            },
      onCancelTrust: () => dispatchSync(SetTrustPendingAction(null)),
      tlsTone: pendingRow != null ? Tone.warn : Tone.good,
    );
  }

  /// The range and the port of *Probe a range*: what was typed, else the
  /// /24 around this computer and the port of the gateway in the field.
  (String, String) _rangeAndPort() {
    final field = parseGateways(login.gateway ?? '').firstOrNull;
    return (
      discovery.range ?? discovery.subnet ?? '',
      discovery.rangePort ?? '${field?.port ?? 8446}',
    );
  }

  static String? _rangeError(String range) {
    try {
      rangeAddresses(range);
      return null;
    } on RangeFormatException catch (e) {
      return switch (e.fault) {
        RangeFault.badText => S.current.rangeBadText,
        RangeFault.badPart => S.current.rangeBadPart,
        RangeFault.badPrefix => S.current.rangeBadPrefix,
        RangeFault.tooBig => S.current.rangeTooBig,
      };
    }
  }

  static String? _portError(String port) {
    final p = int.tryParse(port);
    return p == null || p < 1 || p > 65535 ? S.current.portBad : null;
  }

  /// Where the person allows Studio to see the local network: macOS and
  /// iOS only (spec §4, *Nothing*).
  static VoidCallback? get _settings => switch (defaultTargetPlatform) {
    TargetPlatform.macOS => () => unawaited(
      launchUrl(
        Uri.parse(
          'x-apple.systempreferences:com.apple.preference.security'
          '?Privacy_LocalNetwork',
        ),
      ),
    ),
    TargetPlatform.iOS => () => unawaited(
      launchUrl(Uri.parse('app-settings:')),
    ),
    _ => null,
  };

  /// The panel of found gateways (docs/design/specs/unlock-discover.md §4).
  DiscoverPanelVm _discover() {
    final where = discovery.network == null
        ? S.current.thisNetwork
        : '${discovery.network}'
              '${discovery.subnet == null ? '' : ' (${discovery.subnet})'}';
    final rows = discovery.found.values.toList()
      ..sort((a, b) {
        // Usable rows first, then by site.
        final ua = a.problem == null ? 0 : 1;
        final ub = b.problem == null ? 0 : 1;
        return ua != ub ? ua - ub : a.site.compareTo(b.site);
      });
    final probed = discovery.probing;
    final (range, port) = _rangeAndPort();
    final none = discovery.ended && rows.isEmpty;
    return DiscoverPanelVm(
      title: discovery.scanning
          ? (probed
                ? S.current.discoverProbing(range, port)
                : S.current.discoverLooking(where))
          : rows.isEmpty
          ? S.current.discoverNothing
          : probed
          ? S.current.discoverProbed(rows.length, range)
          : S.current.discoverFound(rows.length, where),
      scanning: discovery.scanning,
      rows: [for (final r in rows) _row(r)],
      none: none
          ? DiscoverNoneVm(
              title: S.current.discoverNoneTitle(where),
              reasons: [
                DiscoverReasonVm(S.current.whyMulticast),
                DiscoverReasonVm(
                  switch (defaultTargetPlatform) {
                    TargetPlatform.macOS => S.current.whyPermissionMac,
                    TargetPlatform.iOS => S.current.whyPermissionIos,
                    _ => S.current.whyPermission,
                  },
                  settings: _settings == null ? null : S.current.openSettings,
                ),
                DiscoverReasonVm(S.current.whyAnnounce, tone: Tone.neutral),
                DiscoverReasonVm(S.current.whyType, tone: Tone.good),
              ],
              range: FieldVm(
                value: range,
                onChanged: (v) => dispatchSync(SetRangeAction(v)),
                error: range.isEmpty ? null : _rangeError(range),
              ),
              port: FieldVm(
                value: port,
                onChanged: (v) => dispatchSync(SetRangePortAction(v)),
                error: port.isEmpty ? null : _portError(port),
              ),
            )
          : null,
    );
  }

  FoundGatewayRowVm _row(FoundGateway r) {
    final tags = tagsOf(r, login.recent);
    final now = DateTime.now().millisecondsSinceEpoch;
    final ago = ((now - r.seen) / 1000).floor();
    final standby = r.standby == null ? null : Uri.tryParse(r.standby!);
    final hosts = r.hosts.isEmpty ? r.site : r.hosts.first;
    final version = r.version == null || r.version!.isEmpty
        ? null
        : S.current.noteWyrmd(r.version!);
    final url = r.url == null ? null : Uri.tryParse(r.url!);
    final pinned = url == null ? null : discovery.pins[url.origin];
    final known = switch (r) {
      _ when !r.tls => S.current.notePlain,
      _ when pinned != null => S.current.notePinned(
        pinned.site.isEmpty ? r.site : pinned.site,
      ),
      _ when r.known => S.current.noteTrusted,
      FoundGateway(:final knownAs?) => S.current.noteKnownAs(knownAs),
      _ => S.current.noteNew,
    };
    final problem = switch (r.problem) {
      null => null,
      FoundProblem.plainHttp => S.current.problemPlainHttp,
      FoundProblem.noInfo => S.current.problemNoInfo,
      FoundProblem.studioTooOld => S.current.problemStudioTooOld(
        r.detail ?? '',
      ),
      FoundProblem.codeMismatch => S.current.problemCodeMismatch,
      FoundProblem.noName => S.current.problemNoName,
      FoundProblem.noAnswer => S.current.problemNoAnswer(r.detail ?? ''),
      FoundProblem.noCa => S.current.problemNoCa,
    };
    final fresh = tags.contains(FoundTag.fresh);
    return FoundGatewayRowVm(
      id: r.site,
      site: r.site,
      tags: [
        for (final t in tags)
          switch (t) {
            FoundTag.usedBefore => FoundTagVm(
              S.current.tagUsedBefore,
              Tone.good,
            ),
            FoundTag.activeStandby => FoundTagVm(
              S.current.tagActiveStandby,
              Tone.ember,
            ),
            FoundTag.downstream => FoundTagVm(
              S.current.tagDownstreamOf(r.up.join(', ')),
              Tone.neutral,
            ),
            FoundTag.fresh => FoundTagVm(S.current.tagNew, Tone.warn),
            FoundTag.plainHttp => FoundTagVm(
              S.current.tagPlainHttp,
              Tone.bad,
            ),
          },
      ],
      hosts: standby == null
          ? hosts
          : S.current.hostsWithStandby(
              hosts,
              '${standby.host}:${standby.port}',
            ),
      note: problem ?? [?version, known].join(' · '),
      noteTone: problem != null
          ? Tone.bad
          : fresh
          ? Tone.warn
          : Tone.neutral,
      dot: problem != null
          ? Tone.bad
          : fresh
          ? Tone.warn
          : Tone.good,
      seen: ago < 2 ? S.current.seenNow : S.current.seenAgo('$ago'),
      selected: discovery.picked == r.site,
      enabled: r.problem == null && r.url != null,
    );
  }

  /// The certificate check of [r] (spec §4, *Trust*).
  TrustCardVm _trust(FoundGateway r) {
    final url = r.url == null ? null : Uri.tryParse(r.url!);
    return TrustCardVm(
      title: S.current.trustTitle(r.site),
      why: S.current.trustWhy(r.site),
      code: codeGroups(r.code ?? ''),
      where: S.current.trustWhere('wyrmd ca fingerprint'),
      command: 'wyrmd ca fingerprint',
      trust: S.current.trustMatches(r.site),
      refused: switch (discovery.trustRefused) {
        null => null,
        TrustRefusal.changed => S.current.trustRefusedChanged,
        TrustRefusal.mismatch => S.current.trustRefusedMismatch,
        TrustRefusal.chain => S.current.trustRefusedChain(url?.host ?? ''),
        _ => S.current.trustRefusedNoAnswer,
      },
      busy: discovery.isWaiting,
    );
  }

  /// The offer after a password login (board `UnlockOffer`).
  UnlockOfferVm _offer(Uri? standby) {
    final d = device;
    final s = S.current;
    final platform = devicePlatform();
    final name = unlockName(d.kind);
    final siteName = site.name ?? d.keySite ?? '';
    final user = _userName(site.user ?? login.user ?? '');
    final role = site.role ?? '';
    final policy = d.policy;
    final faces = unlockGlyph(d.kind) == BiometricGlyph.face;
    final checked = s.unlockOfferChecked(siteName, user, role);
    final line = s.unlockPolicyLine(siteName, policy?.maxPerUser ?? 5);
    if (!d.available) {
      return UnlockOfferVm(
        checked: checked,
        glyph: BiometricGlyph.key,
        title: s.unlockNoBioTitle,
        text: s.unlockNoBioText,
        facts: [
          OfferFactVm(s.unlockNoBioFactRemember),
          OfferFactVm(s.unlockNoBioFactOther, tone: Tone.neutral),
        ],
        policy: line,
        open: s.unlockOpenStudio,
      );
    }
    return UnlockOfferVm(
      checked: checked,
      glyph: unlockGlyph(d.kind),
      title: s.unlockOfferTitle(name),
      text: s.unlockOfferText(name, siteName, unlockDevice(platform)),
      facts: [
        OfferFactVm(s.unlockFactStore(user, siteName, unlockStore(platform))),
        OfferFactVm(
          standby == null
              ? s.unlockFactSite(siteName)
              : s.unlockFactStandby(siteName, standby.host),
        ),
        OfferFactVm(
          faces ? s.unlockFactEndsFaces : s.unlockFactEndsFingers,
          tone: Tone.warn,
        ),
        OfferFactVm(
          s.unlockFactPassword(siteName, policy?.passwordEveryDays ?? 30),
          tone: Tone.neutral,
        ),
      ],
      policy: line,
      use: s.unlockUse(name),
      notNow: s.unlockNotNow,
      dontAsk: s.unlockDontAsk,
      busy: state.wait.isWaitingForType<EnableDeviceAction>(),
    );
  }

  /// The unlock forms (boards `Unlock`, `UnlockFallback`, `UnlockChanged`,
  /// `UnlockSignedOut`, `UnlockLinux`); null for the password form of
  /// login.md.
  UnlockPanelVm? _unlock({
    required String main,
    required Uri? standby,
    required bool down,
    required String tls,
  }) {
    final d = device;
    final stage = d.stage;
    const shown = {
      UnlockStage.unlock,
      UnlockStage.checking,
      UnlockStage.fallback,
      UnlockStage.changed,
      UnlockStage.signedOut,
      UnlockStage.noBiometrics,
    };
    if (!shown.contains(stage)) {
      return null;
    }
    final s = S.current;
    final platform = devicePlatform();
    final name = unlockName(d.kind);
    final glyph = unlockGlyph(d.kind);
    final faces = glyph == BiometricGlyph.face;
    final where = unlockDevice(platform);
    final siteName = d.keySite ?? shortHost(parseGateways(main).first);
    final user = (login.user ?? '').trim();
    final days = d.policy?.passwordEveryDays ?? 30;
    final bio = stage == UnlockStage.unlock || stage == UnlockStage.checking;
    final uri = parseGateways(main).firstOrNull;
    final host = uri == null ? main : '${uri.host}:${uri.port}';
    final notice = switch (stage) {
      UnlockStage.fallback when d.reason != null => UnlockNoticeVm(
        title: d.reason == 'locked out'
            ? s.unlockLockoutTitle(name)
            : s.unlockCancelTitle(name),
        text: s.unlockFallbackText(name),
      ),
      UnlockStage.changed => UnlockNoticeVm(
        title: s.unlockChangedTitle(name),
        text: faces
            ? s.unlockChangedFaces(where)
            : s.unlockChangedFingers(where),
      ),
      UnlockStage.signedOut => switch (d.refusal) {
        UnlockRefusal.removed => UnlockNoticeVm(
          title: s.unlockRemovedTitle,
          text: s.unlockRemovedText(where, name),
          tone: Tone.bad,
        ),
        UnlockRefusal.passwordDue => UnlockNoticeVm(
          title: s.unlockDueTitle(siteName, days),
          text: s.unlockDueText(days, name),
          tone: Tone.bad,
        ),
        UnlockRefusal.passwordChanged => UnlockNoticeVm(
          title: s.unlockPasswordChangedTitle,
          text: s.unlockPasswordChangedText,
          tone: Tone.bad,
        ),
        UnlockRefusal.devicesOff => UnlockNoticeVm(
          title: s.unlockOffTitle(siteName),
          text: s.unlockOffText,
          tone: Tone.bad,
        ),
        _ => UnlockNoticeVm(
          title: s.unlockUnknownTitle(siteName),
          text: s.unlockUnknownText(where, name),
          tone: Tone.bad,
        ),
      },
      UnlockStage.noBiometrics => UnlockNoticeVm(
        title: s.unlockNoneTitle,
        text: platform == 'linux' ? s.unlockNoneLinux : s.unlockNoneOther,
        tone: Tone.neutral,
      ),
      _ => null,
    };
    // Re-enable is offered after changed and signed out, not after
    // devices_off (nothing to turn on) nor password_due (the key stays).
    final reEnable =
        stage == UnlockStage.changed ||
        (stage == UnlockStage.signedOut &&
            d.refusal != UnlockRefusal.devicesOff &&
            d.refusal != UnlockRefusal.passwordDue);
    final keyLine =
        d.keyId == null ||
            stage == UnlockStage.changed ||
            stage == UnlockStage.signedOut
        ? tls
        : s.unlockKeyIn(unlockStore(platform), shortDate(d.added));
    return UnlockPanelVm(
      title: bio ? s.unlockWelcomeBack : s.logIn,
      subtitle: bio ? s.unlockToOpen(siteName) : s.unlockLogInTo(siteName),
      notice: notice,
      account: UnlockAccountVm(
        initials: initialsOf(user),
        user: user,
        role: d.keyRole == null ? '' : s.unlockRoleOn(d.keyRole!, siteName),
        host: standby == null ? host : s.unlockPlusStandby(host),
        tone: down ? Tone.bad : Tone.good,
        last: d.keyId == null || d.lastUsed == 0
            ? s.unlockLastPassword
            : s.unlockLastUsed(name, agoOf(d.lastUsed)),
      ),
      password: !bio,
      glyph: glyph,
      unlockLabel: s.unlockWith(name),
      note: stage == UnlockStage.checking
          ? s.unlockChecking(siteName)
          : s.unlockOrEnter,
      checking: stage == UnlockStage.checking,
      passwordLabel: s.unlockPasswordFor(user),
      reEnable: reEnable && d.available ? s.unlockReEnable(name) : null,
      usePassword: s.unlockUsePassword,
      another: s.unlockAnother,
      footer: keyLine,
      version: s.studioVersion(studioVersion, s.languageName),
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
    required this.onFind,
    required this.discover,
    required this.onLookAgain,
    required this.onPick,
    required this.onProbe,
    required this.onOpenSettings,
    required this.trust,
    required this.onTrust,
    required this.onCancelTrust,
    required this.tlsTone,
    required this.offer,
    required this.onOfferUse,
    required this.onOfferNotNow,
    required this.onOfferDontAsk,
    required this.unlock,
    required this.reEnable,
    required this.onUnlock,
    required this.onAutoUnlock,
    required this.onUsePassword,
    required this.onAnotherAccount,
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
           onFind != null,
           discover,
           onOpenSettings != null,
           trust,
           tlsTone,
           offer,
           unlock,
           reEnable,
           onUnlock != null,
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
  final VoidCallback? onFind;
  final DiscoverPanelVm? discover;
  final VoidCallback onLookAgain;
  final ValueChanged<String> onPick;
  final VoidCallback onProbe;
  final VoidCallback? onOpenSettings;
  final TrustCardVm? trust;
  final VoidCallback? onTrust;
  final VoidCallback onCancelTrust;
  final Tone tlsTone;
  final UnlockOfferVm? offer;
  final VoidCallback onOfferUse;
  final VoidCallback onOfferNotNow;
  final VoidCallback onOfferDontAsk;
  final UnlockPanelVm? unlock;
  final FieldVm<bool> reEnable;
  final VoidCallback? onUnlock;
  final VoidCallback? onAutoUnlock;
  final VoidCallback onUsePassword;
  final VoidCallback onAnotherAccount;
}
