import 'package:business/wyrm/discovery.dart' show FoundTag, RangeFault;
import 'package:business/wyrm/log_in_page.dart';
import 'package:models/found_problem.dart';
import 'package:models/host_platform.dart';
import 'package:models/lock_error.dart';
import 'package:models/step_up_error.dart';
import 'package:models/trust_refusal.dart';
import 'package:models/unlock_fallback.dart';
import 'package:models/unlock_refusal.dart';
import 'package:models/unlock_stage.dart';
import 'package:ui/models/gateway_note.dart';
import 'package:ui/models/tone.dart';
import 'package:ui/overlays/lock_screen.dart';
import 'package:ui/overlays/step_up_dialog.dart';
import 'package:ui/overlays/step_up_screen.dart';
import 'package:ui/pages/log_in_data.dart';
import 'package:wyrm_client/wyrm_client.dart' show Perm;

// The log-in page's, the lock's and the step-up's domain values as `ui`
// draws them: one exhaustive switch per enum or union (studio-rules §3). A
// new domain value is a compile error here, not a silent default on a
// screen.

extension GatewayReachLogIn on GatewayReach {
  LogInReach get reach => switch (this) {
    GatewayReach.unknown => .unknown,
    GatewayReach.answered => .answered,
    GatewayReach.down => .down,
  };
}

extension FieldStateTone on FieldState {
  /// The field's dot.
  Tone get tone => switch (this) {
    FieldState.trustPending => Tone.warn,
    FieldState.down => Tone.bad,
    FieldState.unknown => Tone.neutral,
    FieldState.answered => Tone.good,
  };
}

extension FieldNoteLine on FieldNote {
  GatewayNote get note => switch (this) {
    FieldAnswered(:final label, :final ms) => GatewayNote.answered(label, ms),
    FieldNoAnswer(:final label) => GatewayNote.noAnswer(label),
    FieldPicked(:final site, withStandby: false) => GatewayNote.picked(site),
    FieldPicked(:final site, withStandby: true) =>
      GatewayNote.pickedWithStandby(site),
    FieldEmpty() => const GatewayNote.typeOrFind(),
  };
}

extension RecentGatewayChip on RecentGateway {
  RecentGatewayData get chip => RecentGatewayData(
    text: text,
    label: label,
    reach: reach.reach,
    current: current,
  );
}

extension TlsLineNote on TlsLine {
  TlsNote get note => switch (this) {
    TlsNotTrusted(:final site) => TlsNote.notTrusted(site),
    TlsPinned(:final site) => TlsNote.pinned(site),
    TlsCertificate(:final site) => TlsNote.certificate(site),
  };
}

extension UnlockStageForm on UnlockStage {
  /// The unlock form of this stage; null for the password form of
  /// login.md and for the offer.
  UnlockForm? get form => switch (this) {
    UnlockStage.unlock => .unlock,
    UnlockStage.checking => .checking,
    UnlockStage.fallback => .fallback,
    UnlockStage.changed => .changed,
    UnlockStage.signedOut => .signedOut,
    UnlockStage.noBiometrics => .noBiometrics,
    UnlockStage.none || UnlockStage.offer => null,
  };
}

extension UnlockRefusalWhy on UnlockRefusal {
  SignedOutWhy get why => switch (this) {
    UnlockRefusal.removed => .removed,
    UnlockRefusal.passwordChanged => .passwordChanged,
    UnlockRefusal.passwordDue => .passwordDue,
    UnlockRefusal.devicesOff => .devicesOff,
    UnlockRefusal.unknown => .unknown,
  };
}

extension UnlockFallbackWhy on UnlockFallback {
  FallbackWhy get why => switch (this) {
    UnlockFallback.lockedOut => .lockedOut,
    UnlockFallback.notOpened => .notOpened,
  };
}

extension FoundTagKindOf on FoundTag {
  FoundTagKind get kind => switch (this) {
    FoundTag.usedBefore => .usedBefore,
    FoundTag.activeStandby => .activeStandby,
    FoundTag.downstream => .downstream,
    FoundTag.fresh => .fresh,
    FoundTag.plainHttp => .plainHttp,
  };
}

extension FoundKnownCa on FoundKnown {
  FoundCa get ca => switch (this) {
    FoundPlain() => const FoundCa.plain(),
    FoundPinned(:final site) => FoundCa.pinned(site),
    FoundTrusted() => const FoundCa.trusted(),
    FoundKnownAs(:final site) => FoundCa.knownAs(site),
    FoundFresh() => const FoundCa.fresh(),
  };
}

extension FoundProblemKindOf on FoundProblem {
  FoundProblemKind get kind => switch (this) {
    FoundProblem.plainHttp => .plainHttp,
    FoundProblem.noInfo => .noInfo,
    FoundProblem.studioTooOld => .studioTooOld,
    FoundProblem.codeMismatch => .codeMismatch,
    FoundProblem.noName => .noName,
    FoundProblem.noAnswer => .noAnswer,
    FoundProblem.noCa => .noCa,
  };
}

extension FoundRowLine on FoundRow {
  FoundRowData get line => FoundRowData(
    site: site,
    tags: [for (final t in tags) t.kind],
    up: up,
    host: host,
    standbyHost: standbyHost,
    version: version,
    ca: known.ca,
    problem: problem?.kind,
    detail: detail,
    seen: seen,
    selected: selected,
    enabled: enabled,
  );
}

extension RangeFaultProblem on RangeFault {
  RangeProblem get problem => switch (this) {
    RangeFault.badText => .badText,
    RangeFault.badPart => .badPart,
    RangeFault.badPrefix => .badPrefix,
    RangeFault.tooBig => .tooBig,
  };
}

extension HostPlatformPermission on HostPlatform {
  /// Where the person lets Studio see the local network.
  NetworkPermission get permission => switch (this) {
    HostPlatform.macos => .mac,
    HostPlatform.ios => .ios,
    HostPlatform.windows ||
    HostPlatform.android ||
    HostPlatform.linux ||
    HostPlatform.web => .other,
  };
}

extension TrustRefusalCard on TrustRefusal {
  TrustRefused get refused => switch (this) {
    TrustRefusal.noAnswer => .noAnswer,
    TrustRefusal.changed => .changed,
    TrustRefusal.mismatch => .mismatch,
    TrustRefusal.chain => .chain,
  };
}

extension LockErrorProblem on LockError {
  LockProblem get problem => switch (this) {
    LockErrorWrongPassword() => const LockProblem.wrongPassword(),
    LockErrorRefused(:final said) => LockProblem.said(said),
  };
}

extension StepUpErrorProblem on StepUpError {
  StepUpProblem get problem => switch (this) {
    StepUpWrongPassword() => const StepUpProblem.wrongPassword(),
    StepUpStopped() => const StepUpProblem.stopped(),
    StepUpKeyGone() => const StepUpProblem.keyGone(),
    StepUpRefused(:final said) => StepUpProblem.said(said),
  };
}

extension PermStepUpLevel on Perm {
  StepUpLevel get badge => switch (this) {
    Perm.none => .none,
    Perm.list => .list,
    Perm.read => .read,
    Perm.write => .write,
    Perm.config => .config,
  };
}
