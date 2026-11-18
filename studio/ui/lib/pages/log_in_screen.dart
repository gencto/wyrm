import 'package:equatable/equatable.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';

import '../alerts/trust_card.dart';
import '../alerts/unlock_notice.dart';
import '../alerts/unreachable_alert.dart';
import '../buttons/found_gateway_row.dart';
import '../buttons/recent_chip.dart';
import '../containers/discover_panel.dart';
import '../containers/unlock_offer.dart';
import '../containers/unlock_panel.dart';
import '../containers/welcome_panel.dart';
import '../indicators/biometric_icon.dart';
import '../models/gateway_note.dart';
import '../models/tone.dart';
import '../models/value_changed.dart';
import '../shell/window_bar.dart';
import 'log_in_data.dart';
import 'log_in_page.dart';

/// What the log-in page shows, as typed values (login.md,
/// unlock-discover.md); [LogInScreen] words it.
final class LogInScreenVm extends Equatable {
  const LogInScreenVm({
    required this.gateway,
    required this.user,
    required this.password,
    required this.remember,
    required this.reEnable,
    required this.version,
    required this.fieldLabel,
    this.window = const WindowBarVm(),
    this.standby,
    this.busy = false,
    this.reach = Tone.neutral,
    this.note,
    this.checking = false,
    this.recent = const [],
    this.step = 0,
    this.wrong = false,
    this.unreachable,
    this.tls,
    this.standbyHost,
    this.welcome,
    this.offer,
    this.unlock,
    this.discover,
    this.trust,
  });

  final WindowBarVm window;

  /// The main gateway and the standby (null hides `Add a standby
  /// gateway`).
  final FieldVm<String?> gateway;
  final FieldVm<String?>? standby;
  final FieldVm<String?> user;

  /// The password; the page says when the gateway refused it ([wrong]).
  final FieldVm<String?> password;
  final FieldVm<bool> remember;
  final FieldVm<bool> reEnable;

  /// Studio's version, in the footer.
  final String version;

  /// A log-in is in flight.
  final bool busy;

  /// The field's dot.
  final Tone reach;

  /// The status line under the field.
  final GatewayNote? note;
  final bool checking;
  final List<RecentGatewayData> recent;

  /// The field's gateway as the first sign-in step names it.
  final String fieldLabel;

  /// The running step of a log-in, 0-based.
  final int step;
  final bool wrong;
  final UnreachableData? unreachable;
  final TlsNote? tls;

  /// The standby's `host:port` once one is set.
  final String? standbyHost;
  final WelcomeData? welcome;
  final OfferData? offer;
  final UnlockData? unlock;
  final DiscoverData? discover;
  final TrustData? trust;

  @override
  List<Object?> get props => [
    window,
    gateway,
    standby,
    user,
    password,
    remember,
    reEnable,
    version,
    busy,
    reach,
    note,
    checking,
    recent,
    fieldLabel,
    step,
    wrong,
    unreachable,
    tls,
    standbyHost,
    welcome,
    offer,
    unlock,
    discover,
    trust,
  ];
}

/// The log-in page from typed values: it words them in the language on
/// screen and draws them with [LogInPage]. Every control reports to its
/// callback; the page decides nothing.
class LogInScreen extends StatelessWidget {
  const LogInScreen({
    required this.vm,
    required this.onLogIn,
    required this.onGatewayLeave,
    required this.onRecent,
    required this.onLookAgain,
    required this.onPick,
    required this.onProbe,
    required this.onCancelTrust,
    required this.onOfferUse,
    required this.onOfferNotNow,
    required this.onOfferDontAsk,
    required this.onUsePassword,
    required this.onAnotherAccount,
    this.onUseStandby,
    this.onFind,
    this.onOpenSettings,
    this.onTrust,
    this.onUnlock,
    this.onAutoUnlock,
    super.key,
  });

  /// The placeholder of the gateway field.
  static const gatewayHint = 'https://host:port';

  /// The command that shows a broker's CA code on its host.
  static const fingerprintCommand = 'wyrmd ca fingerprint';

  final LogInScreenVm vm;
  final VoidCallback onLogIn;
  final VoidCallback onGatewayLeave;

  /// A recent chip: its gateway text.
  final ValueChanged<String> onRecent;
  final VoidCallback? onUseStandby;
  final VoidCallback? onFind;
  final VoidCallback onLookAgain;

  /// A found row: its site.
  final ValueChanged<String> onPick;
  final VoidCallback onProbe;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onTrust;
  final VoidCallback onCancelTrust;
  final VoidCallback onOfferUse;
  final VoidCallback onOfferNotNow;
  final VoidCallback onOfferDontAsk;

  /// The round button; null while the key cannot be tried.
  final VoidCallback? onUnlock;
  final VoidCallback? onAutoUnlock;
  final VoidCallback onUsePassword;
  final VoidCallback onAnotherAccount;

  @override
  Widget build(BuildContext context) {
    final s = S.current;
    final p = vm.password;
    return LogInPage(
      window: vm.window,
      gateway: vm.gateway,
      user: vm.user,
      password: FieldVm(
        value: p.value,
        onChanged: p.onChanged,
        validator: p.validator,
        error: vm.wrong ? s.wrongPassword : null,
        enabled: p.enabled,
      ),
      isWaiting: vm.busy,
      onPressedLogIn: onLogIn,
      // The board shows the language in use, not a switcher (owner decision
      // 2026-11-08, docs/design/specs/login.md §3.8).
      version: _version(vm.version),
      standby: vm.standby,
      gatewayTone: vm.reach,
      gatewayNote: vm.note,
      checking: vm.checking,
      onGatewayLeave: onGatewayLeave,
      recent: [
        for (final r in vm.recent)
          RecentChipVm(
            id: r.text,
            label: r.label,
            tone: r.reach.tone,
            current: r.current,
          ),
      ],
      onRecent: onRecent,
      remember: vm.remember,
      steps: [
        s.stepReaching(vm.fieldLabel),
        s.stepChecking,
        s.stepReading,
      ],
      step: vm.step,
      wrong: vm.wrong,
      unreachable: switch (vm.unreachable) {
        final u? => UnreachableAlertVm(
          detail: [u.gateway, ?u.reason?.words].join(' · '),
          advice: s.unreachableAdvice,
          standby: u.standby,
        ),
        null => null,
      },
      onRetry: onLogIn,
      onUseStandby: onUseStandby,
      tls: vm.tls?.text,
      tlsTone: vm.tls?.tone ?? Tone.good,
      standbyLabel: switch (vm.standbyHost) {
        final h? => s.standbyIs(h),
        null => null,
      },
      welcome: switch (vm.welcome) {
        final w? => _welcome(w),
        null => null,
      },
      gatewayHint: gatewayHint,
      onFind: onFind,
      discover: switch (vm.discover) {
        final d? => _discover(d),
        null => null,
      },
      onLookAgain: onLookAgain,
      onPick: onPick,
      onProbe: onProbe,
      onOpenSettings: onOpenSettings,
      trust: switch (vm.trust) {
        final t? => _trust(t),
        null => null,
      },
      onTrust: onTrust,
      onCancelTrust: onCancelTrust,
      offer: switch (vm.offer) {
        final o? => _offer(o),
        null => null,
      },
      onOfferUse: onOfferUse,
      onOfferNotNow: onOfferNotNow,
      onOfferDontAsk: onOfferDontAsk,
      unlock: switch (vm.unlock) {
        final u? => _unlock(u),
        null => null,
      },
      reEnable: vm.reEnable,
      onUnlock: onUnlock,
      onAutoUnlock: onAutoUnlock,
      onUsePassword: onUsePassword,
      onAnotherAccount: onAnotherAccount,
    );
  }

  static String _version(String version) =>
      S.current.studioVersion(version, S.current.languageName);

  /// `a`, `a and b`, `a, b and c`.
  static String _list(List<String> items) => switch (items) {
    [] => '',
    [final one] => one,
    [...final head, final last] => S.current.listAnd(head.join(', '), last),
  };

  /// Two letters of a user: `olena` → `OL`.
  static String _initials(String user) {
    final u = user.trim();
    if (u.isEmpty) {
      return '?';
    }
    final parts = u.split(RegExp(r'[\s._-]+')).where((p) => p.isNotEmpty);
    final two = parts.length > 1
        ? '${parts.first[0]}${parts.elementAt(1)[0]}'
        : u.substring(0, u.length < 2 ? u.length : 2);
    return two.toUpperCase();
  }

  /// What is known while the tree opens (login.md §5).
  static WelcomePanelVm _welcome(WelcomeData w) {
    final s = S.current;
    final role = w.role;
    return WelcomePanelVm(
      title: s.welcomeUser(w.user),
      site: w.site,
      // The preload of the welcome, one line a step; a late one says it
      // goes on after Studio opens.
      steps: [
        for (final (i, label) in [
          s.preloadTree(w.site),
          s.preloadFlows,
          s.preloadBlocks,
          s.preloadLinks,
          s.preloadSites,
        ].indexed)
          if (w.late.contains(i)) s.preloadLater(label) else label,
      ],
      step: w.step,
      late: w.late,
      facts: [
        if (role != null && role.isNotEmpty)
          [
            s.roleOnSite(role, w.site),
            if (w.otherSites.isNotEmpty) s.reachesSites(_list(w.otherSites)),
          ].join(' · '),
        if (w.links > 0) s.linksCount(w.links),
      ],
    );
  }

  /// The offer after a password log-in (board `UnlockOffer`).
  static UnlockOfferVm _offer(OfferData o) {
    final s = S.current;
    final name = o.method.label;
    final checked = s.unlockOfferChecked(o.site, o.user, o.role);
    final line = s.unlockPolicyLine(o.site, o.maxPerUser);
    if (!o.biometric) {
      return UnlockOfferVm(
        checked: checked,
        glyph: .key,
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
    final faces = o.method.glyph == BiometricGlyph.face;
    return UnlockOfferVm(
      checked: checked,
      glyph: o.method.glyph,
      title: s.unlockOfferTitle(name),
      text: s.unlockOfferText(name, o.site, o.os.device),
      facts: [
        OfferFactVm(s.unlockFactStore(o.user, o.site, o.os.store)),
        OfferFactVm(switch (o.standbyHost) {
          final h? => s.unlockFactStandby(o.site, h),
          null => s.unlockFactSite(o.site),
        }),
        OfferFactVm(
          faces ? s.unlockFactEndsFaces : s.unlockFactEndsFingers,
          tone: Tone.warn,
        ),
        OfferFactVm(
          s.unlockFactPassword(o.site, o.passwordEveryDays),
          tone: Tone.neutral,
        ),
      ],
      policy: line,
      use: s.unlockUse(name),
      notNow: s.unlockNotNow,
      dontAsk: s.unlockDontAsk,
      busy: o.busy,
    );
  }

  /// The unlock forms (boards `Unlock`, `UnlockFallback`, `UnlockChanged`,
  /// `UnlockSignedOut`, `UnlockLinux`).
  static UnlockPanelVm _unlock(UnlockData u) {
    final s = S.current;
    final name = u.method.label;
    final glyph = u.method.glyph;
    final faces = glyph == BiometricGlyph.face;
    final where = u.os.device;
    final bio = u.form.biometric;
    final notice = switch (u.form) {
      UnlockForm.fallback => switch (u.fallback) {
        null => null,
        final why => UnlockNoticeVm(
          title: why == FallbackWhy.lockedOut
              ? s.unlockLockoutTitle(name)
              : s.unlockCancelTitle(name),
          text: s.unlockFallbackText(name),
        ),
      },
      UnlockForm.changed => UnlockNoticeVm(
        title: s.unlockChangedTitle(name),
        text: faces
            ? s.unlockChangedFaces(where)
            : s.unlockChangedFingers(where),
      ),
      UnlockForm.signedOut => _signedOut(u, name, where),
      UnlockForm.noBiometrics => UnlockNoticeVm(
        title: s.unlockNoneTitle,
        text: u.linux ? s.unlockNoneLinux : s.unlockNoneOther,
        tone: Tone.neutral,
      ),
      UnlockForm.unlock || UnlockForm.checking => null,
    };
    final footer = switch ((u.keyShown, u.tlsSite)) {
      (true, _) => s.unlockKeyIn(
        u.os.store,
        switch (u.keyAdded) {
          final added? => Formats.shortDate(added),
          null => '',
        },
      ),
      (false, final site?) => s.tlsCertificateOf(site),
      (false, null) => '',
    };
    final role = u.role;
    return UnlockPanelVm(
      title: bio ? s.unlockWelcomeBack : s.logIn,
      subtitle: bio ? s.unlockToOpen(u.site) : s.unlockLogInTo(u.site),
      notice: notice,
      account: UnlockAccountVm(
        initials: _initials(u.user),
        user: u.user,
        role: role == null ? '' : s.unlockRoleOn(role, u.site),
        host: u.withStandby ? s.unlockPlusStandby(u.host) : u.host,
        tone: u.down ? Tone.bad : Tone.good,
        last: switch (u.lastUsed) {
          final at? => s.unlockLastUsed(
            name,
            Formats.ago(at, nowWord: s.unlockAgoNow),
          ),
          null => s.unlockLastPassword,
        },
      ),
      password: !bio,
      glyph: glyph,
      unlockLabel: s.unlockWith(name),
      note: u.form == UnlockForm.checking
          ? s.unlockChecking(u.site)
          : s.unlockOrEnter,
      checking: u.form == UnlockForm.checking,
      passwordLabel: s.unlockPasswordFor(u.user),
      reEnable: u.reEnable ? s.unlockReEnable(name) : null,
      usePassword: s.unlockUsePassword,
      another: s.unlockAnother,
      footer: footer,
      version: _version(u.version),
    );
  }

  static UnlockNoticeVm _signedOut(UnlockData u, String name, String where) {
    final s = S.current;
    return switch (u.signedOut) {
      SignedOutWhy.removed => UnlockNoticeVm(
        title: s.unlockRemovedTitle,
        text: s.unlockRemovedText(where, name),
        tone: Tone.bad,
      ),
      SignedOutWhy.passwordDue => UnlockNoticeVm(
        title: s.unlockDueTitle(u.site, u.passwordEveryDays),
        text: s.unlockDueText(u.passwordEveryDays, name),
        tone: Tone.bad,
      ),
      SignedOutWhy.passwordChanged => UnlockNoticeVm(
        title: s.unlockPasswordChangedTitle,
        text: s.unlockPasswordChangedText,
        tone: Tone.bad,
      ),
      SignedOutWhy.devicesOff => UnlockNoticeVm(
        title: s.unlockOffTitle(u.site),
        text: s.unlockOffText,
        tone: Tone.bad,
      ),
      SignedOutWhy.unknown || null => UnlockNoticeVm(
        title: s.unlockUnknownTitle(u.site),
        text: s.unlockUnknownText(where, name),
        tone: Tone.bad,
      ),
    };
  }

  /// The panel of found gateways (unlock-discover.md §4).
  static DiscoverPanelVm _discover(DiscoverData d) {
    final s = S.current;
    final where = switch ((d.network, d.subnet)) {
      (null, _) => s.thisNetwork,
      (final n?, null) => n,
      (final n?, final sub?) => '$n ($sub)',
    };
    final range = d.range.value ?? '';
    final port = d.port.value ?? '';
    final n = d.rows.length;
    return DiscoverPanelVm(
      title: d.scanning
          ? (d.probing
                ? s.discoverProbing(range, port)
                : s.discoverLooking(where))
          : d.rows.isEmpty
          ? s.discoverNothing
          : d.probing
          ? s.discoverProbed(n, range)
          : s.discoverFound(n, where),
      scanning: d.scanning,
      rows: [for (final r in d.rows) _row(r)],
      none: d.ended && d.rows.isEmpty
          ? DiscoverNoneVm(
              title: s.discoverNoneTitle(where),
              reasons: [
                DiscoverReasonVm(s.whyMulticast),
                DiscoverReasonVm(
                  d.permission.text,
                  settings: d.settings ? s.openSettings : null,
                ),
                DiscoverReasonVm(s.whyAnnounce, tone: Tone.neutral),
                DiscoverReasonVm(s.whyType, tone: Tone.good),
              ],
              range: FieldVm(
                value: d.range.value,
                onChanged: d.range.onChanged,
                error: range.isEmpty ? null : d.rangeProblem?.text,
              ),
              port: FieldVm(
                value: d.port.value,
                onChanged: d.port.onChanged,
                error: port.isEmpty || !d.portBad ? null : s.portBad,
              ),
            )
          : null,
    );
  }

  static FoundGatewayRowVm _row(FoundRowData r) {
    final s = S.current;
    final problem = r.problem;
    final seen = r.seen.inSeconds;
    return FoundGatewayRowVm(
      id: r.site,
      site: r.site,
      tags: [for (final t in r.tags) FoundTagVm(t.label(r.up), t.tone)],
      hosts: switch (r.standbyHost) {
        final h? => s.hostsWithStandby(r.host, h),
        null => r.host,
      },
      note: switch (problem) {
        final p? => p.text(r.detail, why: r.why),
        null => [
          if (r.version case final v?) s.noteWyrmd(v),
          r.ca.text,
        ].join(' · '),
      },
      noteTone: problem != null
          ? Tone.bad
          : r.fresh
          ? Tone.warn
          : Tone.neutral,
      dot: problem != null
          ? Tone.bad
          : r.fresh
          ? Tone.warn
          : Tone.good,
      seen: seen < 2 ? s.seenNow : s.seenAgo('$seen'),
      selected: r.selected,
      enabled: r.enabled,
    );
  }

  /// The certificate check of a found gateway (spec §4, *Trust*).
  static TrustCardVm _trust(TrustData t) {
    final s = S.current;
    return TrustCardVm(
      title: s.trustTitle(t.site),
      why: s.trustWhy(t.site),
      code: t.code,
      where: s.trustWhere(fingerprintCommand),
      command: fingerprintCommand,
      trust: s.trustMatches(t.site),
      refused: switch (t.refused) {
        null => null,
        TrustRefused.changed => s.trustRefusedChanged,
        TrustRefused.mismatch => s.trustRefusedMismatch,
        TrustRefused.chain => s.trustRefusedChain(t.host),
        TrustRefused.noAnswer => s.trustRefusedNoAnswer,
      },
      busy: t.busy,
    );
  }
}
