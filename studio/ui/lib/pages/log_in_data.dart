import 'package:equatable/equatable.dart';
import 'package:localization/localization.dart';

import '../indicators/device_os.dart';
import '../indicators/unlock_method.dart';
import '../models/tone.dart';
import '../models/value_changed.dart';

// What the log-in page is drawn from (docs/design/specs/login.md,
// unlock-discover.md), as typed values: the connector maps the domain into
// these; `LogInScreen` words them in the language on screen and draws them
// with `LogInPage` (studio-rules §3, §5).

/// What the last probe of a gateway found, as its dot shows it.
enum LogInReach {
  unknown(Tone.neutral),
  answered(Tone.good),
  down(Tone.bad);

  const LogInReach(this.tone);

  final Tone tone;
}

/// A recent gateway's chip: the field's [text] it puts back, its [label].
final class RecentGatewayData extends Equatable {
  const RecentGatewayData({
    required this.text,
    required this.label,
    required this.reach,
    required this.current,
  });

  final String text;
  final String label;
  final LogInReach reach;
  final bool current;

  @override
  List<Object?> get props => [text, label, reach, current];
}

/// The footer's TLS line of the field's gateway.
sealed class TlsNote extends Equatable {
  const TlsNote(this.site);

  /// `TLS · <site> CA, not trusted yet`: the lock is amber.
  const factory TlsNote.notTrusted(String site) = TlsNotTrustedNote;

  /// `TLS · CA pinned for <site>`.
  const factory TlsNote.pinned(String site) = TlsPinnedNote;

  /// `TLS · certificate of the <site> CA`.
  const factory TlsNote.certificate(String site) = TlsCertificateNote;

  final String site;

  String get text => switch (this) {
    TlsNotTrustedNote() => S.current.tlsNotTrusted(site),
    TlsPinnedNote() => S.current.tlsPinned(site),
    TlsCertificateNote() => S.current.tlsCertificateOf(site),
  };

  /// The lock's colour.
  Tone get tone => switch (this) {
    TlsNotTrustedNote() => Tone.warn,
    TlsPinnedNote() || TlsCertificateNote() => Tone.good,
  };

  @override
  List<Object?> get props => [site];
}

final class TlsNotTrustedNote extends TlsNote {
  const TlsNotTrustedNote(super.site);
}

final class TlsPinnedNote extends TlsNote {
  const TlsPinnedNote(super.site);
}

final class TlsCertificateNote extends TlsNote {
  const TlsCertificateNote(super.site);
}

/// No gateway answered the log-in: the alert above the form.
final class UnreachableData extends Equatable {
  const UnreachableData({required this.gateway, this.reason, this.standby});

  /// The main gateway as typed.
  final String gateway;

  /// What the last probe said (`connection refused after 3 ms`).
  final AnswerWhy? reason;

  /// The standby's `host:port`, when one is set.
  final String? standby;

  @override
  List<Object?> get props => [gateway, reason, standby];
}

/// Logged in, the tree opening (login.md §5).
final class WelcomeData extends Equatable {
  const WelcomeData({
    required this.user,
    required this.site,
    required this.otherSites,
    required this.links,
    required this.step,
    required this.late,
    this.role,
  });

  final String user;
  final String site;

  /// The other sites the user reaches.
  final List<String> otherSites;

  /// The role on the site; null or empty while not known.
  final String? role;

  /// How many links the first list holds.
  final int links;

  /// The preload step running, 0-based.
  final int step;

  /// The steps that did not finish in time.
  final Set<int> late;

  @override
  List<Object?> get props => [user, site, otherSites, role, links, step, late];
}

/// After a password log-in: `Unlock with <name> next time?` (board
/// `UnlockOffer`).
final class OfferData extends Equatable {
  const OfferData({
    required this.method,
    required this.os,
    required this.biometric,
    required this.site,
    required this.user,
    required this.role,
    required this.maxPerUser,
    required this.passwordEveryDays,
    this.standbyHost,
    this.busy = false,
  });

  final UnlockMethod method;

  /// The computer Studio runs on.
  final DeviceOs os;

  /// A biometric is here; without one the offer only says so.
  final bool biometric;
  final String site;
  final String user;
  final String role;
  final int maxPerUser;
  final int passwordEveryDays;

  /// The standby's host, when the field has one.
  final String? standbyHost;

  /// The key is being made.
  final bool busy;

  @override
  List<Object?> get props => [
    method,
    os,
    biometric,
    site,
    user,
    role,
    maxPerUser,
    passwordEveryDays,
    standbyHost,
    busy,
  ];
}

/// Which unlock form the page shows (unlock-discover.md §2).
enum UnlockForm {
  /// `Welcome back`: the round button.
  unlock,

  /// The gateway checks the signed key.
  checking,

  /// The password, the key kept.
  fallback,

  /// Fingerprints or faces changed: the key is gone.
  changed,

  /// The gateway refused the key.
  signedOut,

  /// No biometric unlock on this computer.
  noBiometrics;

  /// The round button shows, not the password.
  bool get biometric => switch (this) {
    unlock || checking => true,
    fallback || changed || signedOut || noBiometrics => false,
  };
}

/// Why the gateway refused the key (board `UnlockSignedOut`).
enum SignedOutWhy { removed, passwordChanged, passwordDue, devicesOff, unknown }

/// Why the page fell back to the password (board `UnlockFallback`).
enum FallbackWhy { lockedOut, notOpened }

/// The unlock form while a device key is in play.
final class UnlockData extends Equatable {
  const UnlockData({
    required this.form,
    required this.method,
    required this.os,
    required this.site,
    required this.user,
    required this.host,
    required this.withStandby,
    required this.down,
    required this.passwordEveryDays,
    required this.version,
    this.fallback,
    this.signedOut,
    this.linux = false,
    this.role,
    this.lastUsed,
    this.keyShown = false,
    this.keyAdded,
    this.tlsSite,
    this.reEnable = false,
  });

  final UnlockForm form;
  final FallbackWhy? fallback;
  final SignedOutWhy? signedOut;
  final UnlockMethod method;

  /// The computer Studio runs on.
  final DeviceOs os;

  /// It is Linux (the no-biometric notice says so).
  final bool linux;
  final String site;
  final String user;

  /// The role of the key's user on the site; null while not known.
  final String? role;

  /// `host:port` of the gateway.
  final String host;
  final bool withStandby;

  /// The gateway did not answer: the account card's dot is red.
  final bool down;
  final int passwordEveryDays;

  /// When the key last unlocked; null for a password log-in.
  final DateTime? lastUsed;

  /// The footer names the key (`Key in … · added …`), not the TLS line.
  final bool keyShown;

  /// When the key was made; null when not known.
  final DateTime? keyAdded;

  /// The site of the TLS line of an `https` gateway; null for none.
  final String? tlsSite;

  /// `Turn <name> on again after I log in` is offered.
  final bool reEnable;

  /// Studio's version, in the footer.
  final String version;

  @override
  List<Object?> get props => [
    form,
    fallback,
    signedOut,
    method,
    os,
    linux,
    site,
    user,
    role,
    host,
    withStandby,
    down,
    passwordEveryDays,
    lastUsed,
    keyShown,
    keyAdded,
    tlsSite,
    reEnable,
    version,
  ];
}

/// A tag of a found row (unlock-discover.md §4).
enum FoundTagKind {
  usedBefore(Tone.good),
  activeStandby(Tone.ember),
  downstream(Tone.neutral),
  fresh(Tone.warn),
  plainHttp(Tone.bad);

  const FoundTagKind(this.tone);

  final Tone tone;

  /// Its words; a downstream names the sites [up].
  String label(List<String> up) => switch (this) {
    usedBefore => S.current.tagUsedBefore,
    activeStandby => S.current.tagActiveStandby,
    downstream => S.current.tagDownstreamOf(up.join(', ')),
    fresh => S.current.tagNew,
    plainHttp => S.current.tagPlainHttp,
  };
}

/// What is known of a found row's CA.
sealed class FoundCa extends Equatable {
  const FoundCa();

  /// Plain HTTP on this computer.
  const factory FoundCa.plain() = FoundCaPlain;

  /// Pinned for [site].
  const factory FoundCa.pinned(String site) = FoundCaPinned;

  /// Trusted by this computer.
  const factory FoundCa.trusted() = FoundCaTrusted;

  /// Signed by the CA pinned for [site].
  const factory FoundCa.knownAs(String site) = FoundCaKnownAs;

  /// Its own CA: check the code.
  const factory FoundCa.fresh() = FoundCaFresh;

  String get text => switch (this) {
    FoundCaPlain() => S.current.notePlain,
    FoundCaPinned(:final site) => S.current.notePinned(site),
    FoundCaTrusted() => S.current.noteTrusted,
    FoundCaKnownAs(:final site) => S.current.noteKnownAs(site),
    FoundCaFresh() => S.current.noteNew,
  };
}

final class FoundCaPlain extends FoundCa {
  const FoundCaPlain();
  @override
  List<Object?> get props => const [];
}

final class FoundCaPinned extends FoundCa {
  const FoundCaPinned(this.site);
  final String site;
  @override
  List<Object?> get props => [site];
}

final class FoundCaTrusted extends FoundCa {
  const FoundCaTrusted();
  @override
  List<Object?> get props => const [];
}

final class FoundCaKnownAs extends FoundCa {
  const FoundCaKnownAs(this.site);
  final String site;
  @override
  List<Object?> get props => [site];
}

final class FoundCaFresh extends FoundCa {
  const FoundCaFresh();
  @override
  List<Object?> get props => const [];
}

/// Why a found row cannot be picked.
enum FoundProblemKind {
  plainHttp,
  noInfo,
  studioTooOld,
  codeMismatch,
  noName,
  noAnswer,
  noCa;

  /// Its words, with the [detail] it came with (a version) and [why]
  /// there was no answer.
  String text(String detail, {AnswerWhy? why}) => switch (this) {
    plainHttp => S.current.problemPlainHttp,
    noInfo => S.current.problemNoInfo,
    studioTooOld => S.current.problemStudioTooOld(detail),
    codeMismatch => S.current.problemCodeMismatch,
    noName => S.current.problemNoName,
    noAnswer => S.current.problemNoAnswer(why?.words ?? detail),
    noCa => S.current.problemNoCa,
  };
}

/// Why a gateway's `/api/info` gave nothing, said in the row's note.
final class AnswerWhy extends Equatable {
  const AnswerWhy.timedOut() : this._(_Why.timedOut);
  const AnswerWhy.notGateway() : this._(_Why.notGateway);

  /// The field at [path] of its answer is not what belongs there.
  const AnswerWhy.wrongShape(String path) : this._(_Why.wrongShape, text: path);
  const AnswerWhy.http(int code) : this._(_Why.http, code: code);
  const AnswerWhy.untrusted() : this._(_Why.untrusted);

  /// The connection was refused [ms] milliseconds after it was tried.
  const AnswerWhy.refusedAfter(int ms) : this._(_Why.refusedAfter, code: ms);
  const AnswerWhy.noRoute() : this._(_Why.noRoute);

  /// Something else was thrown: the name of its type.
  const AnswerWhy.failed(String type) : this._(_Why.failed, text: type);

  /// The system's own words, as they came.
  const AnswerWhy.said(String text) : this._(_Why.said, text: text);

  const AnswerWhy._(
    this._kind, {
    this._text = '',
    this._code = 0,
  });

  final _Why _kind;
  final String _text;
  final int _code;

  String get words => switch (_kind) {
    _Why.timedOut => S.current.answerTimedOut,
    _Why.notGateway => S.current.answerNotGateway,
    _Why.wrongShape => S.current.answerWrongShape(_text),
    _Why.http => S.current.answerHttp(_code),
    _Why.untrusted => S.current.answerUntrusted,
    // under a second in milliseconds, else in whole seconds
    _Why.refusedAfter => S.current.answerRefusedAfter(
      _code < 1000
          ? S.current.answerMs(_code)
          : S.current.answerSeconds(_code ~/ 1000),
    ),
    _Why.noRoute => S.current.answerNoRoute,
    _Why.failed => S.current.answerFailed(_text),
    _Why.said => _text,
  };

  @override
  List<Object?> get props => [_kind, _text, _code];
}

enum _Why {
  timedOut,
  notGateway,
  wrongShape,
  http,
  untrusted,
  refusedAfter,
  noRoute,
  failed,
  said,
}

/// A found gateway's row.
final class FoundRowData extends Equatable {
  const FoundRowData({
    required this.site,
    required this.tags,
    required this.up,
    required this.host,
    required this.ca,
    required this.seen,
    this.standbyHost,
    this.version,
    this.problem,
    this.detail = '',
    this.why,
    this.selected = false,
    this.enabled = true,
  });

  final String site;
  final List<FoundTagKind> tags;

  /// The sites it is a downstream of.
  final List<String> up;
  final String host;
  final String? standbyHost;
  final String? version;
  final FoundCa ca;
  final FoundProblemKind? problem;
  final String detail;

  /// Why there was no answer, when that is the [problem].
  final AnswerWhy? why;

  /// How long ago it was last seen, in whole seconds.
  final Duration seen;
  final bool selected;
  final bool enabled;

  /// A CA not known here.
  bool get fresh => tags.contains(FoundTagKind.fresh);

  @override
  List<Object?> get props => [
    site,
    tags,
    up,
    host,
    standbyHost,
    version,
    ca,
    problem,
    detail,
    why,
    seen,
    selected,
    enabled,
  ];
}

/// What is wrong with the range to probe.
enum RangeProblem {
  badText,
  badPart,
  badPrefix,
  tooBig;

  String get text => switch (this) {
    badText => S.current.rangeBadText,
    badPart => S.current.rangeBadPart,
    badPrefix => S.current.rangeBadPrefix,
    tooBig => S.current.rangeTooBig,
  };
}

/// Where Studio asks for the local network permission.
enum NetworkPermission {
  mac,
  ios,
  other;

  String get text => switch (this) {
    mac => S.current.whyPermissionMac,
    ios => S.current.whyPermissionIos,
    other => S.current.whyPermission,
  };
}

/// *Find on this network* (unlock-discover.md §4).
final class DiscoverData extends Equatable {
  const DiscoverData({
    required this.rows,
    required this.scanning,
    required this.probing,
    required this.ended,
    required this.range,
    required this.port,
    required this.permission,
    required this.settings,
    this.network,
    this.subnet,
    this.rangeProblem,
    this.portBad = false,
  });

  final List<FoundRowData> rows;
  final bool scanning;

  /// A range probe, not a browse.
  final bool probing;

  /// The search ended.
  final bool ended;

  /// The interface it looks on, `en0`; null when none is known.
  final String? network;

  /// The /24 around this computer.
  final String? subnet;

  /// The range and the port of *Probe a range*, as typed (or their
  /// defaults); their faults are said under them.
  final FieldVm<String?> range;
  final FieldVm<String?> port;
  final RangeProblem? rangeProblem;
  final bool portBad;
  final NetworkPermission permission;

  /// *Open settings* is offered (macOS, iOS).
  final bool settings;

  @override
  List<Object?> get props => [
    rows,
    scanning,
    probing,
    ended,
    network,
    subnet,
    range,
    port,
    rangeProblem,
    portBad,
    permission,
    settings,
  ];
}

/// Why a trust pinned nothing.
enum TrustRefused { noAnswer, changed, mismatch, chain }

/// The certificate check of a found gateway (unlock-discover.md §4).
final class TrustData extends Equatable {
  const TrustData({
    required this.site,
    required this.code,
    required this.host,
    this.refused,
    this.busy = false,
  });

  final String site;

  /// The CA code Studio computed from the CA's bytes, in groups of 4.
  final List<String> code;

  /// The host its certificate must name.
  final String host;
  final TrustRefused? refused;
  final bool busy;

  @override
  List<Object?> get props => [site, code, host, refused, busy];
}
