import 'dart:io';

import 'package:business/wyrm/device_keys.dart';
import 'package:business/wyrm/failures.dart';
import 'package:business/wyrm/keys.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:localization/localization.dart';
import 'package:models/call_verb.dart';
import 'package:models/error_hint.dart';
import 'package:models/error_kind.dart';
import 'package:models/known_call.dart';
import 'package:models/studio_error.dart';
import 'package:ui/alerts/toast_stack.dart';
import 'package:ui/dialogs/error_dialog.dart';
import 'package:ui/models/tone.dart';
import 'package:ui/overlays/problems_drawer.dart';

import 'common/studio_version.dart';
import 'mappers/device_mappers.dart';

// The words of an error (docs/design/specs/errors.md §1, §3, §7). They live
// in `app` because this is the only package that may name `S`: `business`
// keeps a failure as data (kind, status, call, key, thing, site) and asks
// for its words through `ErrorWording`.

/// `1.0 (macOS 15.1)`: Studio's version and the system it runs on.
String get studioAbout {
  final os = hostPlatform().os.system;
  // `Version 15.1 (Build 24B83)` → `15.1`.
  final version = kIsWeb
      ? null
      : RegExp(
          r'\d+(\.\d+)+',
        ).firstMatch(Platform.operatingSystemVersion)?.group(0);
  return S.current.studioAbout(
    studioVersion,
    version == null ? os : '$os $version',
  );
}

/// The name of what [e] was about: given by the caller, else the last
/// segment of the key, else `this`.
String _thing(StudioError e) => switch (e.subject) {
  .assistant => S.current.errThingAssistant,
  .profile => S.current.errThingProfile,
  .device => S.current.errThingDevice(e.thing ?? ''),
  .biometrics => S.current.unlockNameBiometric,
  null => switch (e.thing) {
    final t? when t.isNotEmpty => t,
    _ => lastNameOf(e.key) ?? e.site ?? S.current.errThingThis,
  },
};

/// What the call of [e] does; one Studio does not know by name is run.
CallVerb _verb(StudioError e) => e.call?.verb ?? .run;

/// `deploy pump-control`: after `You can’t` and `Studio could not`.
String _toDo(StudioError e) {
  final s = S.current;
  final t = _thing(e);
  return switch (_verb(e)) {
    .deploy => s.errDoDeploy(t),
    .install => s.errDoInstall(t),
    .write => s.errDoWrite(t),
    .read => s.errDoRead(t),
    .list => s.errDoList(t),
    .remove => s.errDoRemove(t),
    .save => s.errDoSave(t),
    .start => s.errDoStart(t),
    .stop => s.errDoStop(t),
    .open => s.errDoOpen(t),
    .logIn => s.errDoLogIn(t),
    .run => switch (e.call) {
      final c? => s.errDoRun(c.name, t),
      null => s.errDoStep(t),
    },
  };
}

/// `Installing modbus 0.4.2`: before `failed on plant`.
String _doing(StudioError e) {
  final s = S.current;
  final t = _thing(e);
  return switch (_verb(e)) {
    .deploy => s.errDoingDeploy(t),
    .install => s.errDoingInstall(t),
    .write => s.errDoingWrite(t),
    .read => s.errDoingRead(t),
    .list => s.errDoingList(t),
    .remove => s.errDoingRemove(t),
    .save => s.errDoingSave(t),
    .start => s.errDoingStart(t),
    .stop => s.errDoingStop(t),
    .open => s.errDoingOpen(t),
    .logIn => s.errDoingLogIn(t),
    .run => s.errDoingRun(e.call?.name ?? '', t),
  };
}

/// `the install`: before `did not start`.
String _noun(StudioError e) {
  final s = S.current;
  return switch (_verb(e)) {
    .deploy => s.errNounDeploy,
    .install => s.errNounInstall,
    .write => s.errNounWrite,
    .read => s.errNounRead,
    .list => s.errNounList,
    .remove => s.errNounRemove,
    .save => s.errNounSave,
    .start => s.errNounStart,
    .stop => s.errNounStop,
    .open => s.errNounOpen,
    .logIn => s.errNounLogIn,
    .run => s.errNounRun(e.call?.name ?? ''),
  };
}

/// Who did not answer: the site, when the broker there was silent (a
/// timeout); the link, when the broker answered that the link below it is
/// not connected (`disconnected`, `not_available`, `closed` on a key under
/// `downstream/<link>`).
String? _unreached(StudioError e) {
  final parts = e.key?.split('/') ?? const <String>[];
  final link = parts.length > 3 && parts[2] == 'downstream' ? parts[3] : null;
  return isTimeout(e) || link == null ? e.site : link;
}

/// The title of [e]: what did not happen, with its object (errors.md §7).
/// Never `Error` or `Something went wrong`.
String errorTitle(StudioError e) {
  final s = S.current;
  // What Studio did on its own reads as what the user sees stop.
  if (e.stream case final site?) {
    return s.errTitleStream(site);
  }
  final call = e.call?.known;
  if (e.quiet && call == KnownCall.subscribe) {
    return s.errTitleRead(_thing(e));
  }
  if (call == KnownCall.history) {
    return s.errTitleHistory(_thing(e));
  }
  // The offer's `Use <name>` or the Security switch (unlock-discover.md §2):
  // `Touch ID could not be turned on`, the reason under it.
  if (call == KnownCall.enableDevice) {
    return s.unlockOffToast(_thing(e));
  }
  // Said by Studio, not by the broker: a file it cannot read, a fault.
  final own = e.status == null && e.kind != .broker;
  return switch (e.kind) {
    .studio =>
      e.report != null
          ? s.errTitleStudio(s.errDoStep(e.call?.name ?? s.errThingThis))
          : e.call == null
          ? s.errTitlePlain
          : s.errTitleStudio(_toDo(e)),
    .reach when e.call == null && e.key == null => s.errTitleNotConnected,
    .reach when call == KnownCall.logIn || call == KnownCall.me =>
      s.errTitleReach(
        _thing(e),
      ),
    .reach => switch (_unreached(e)) {
      final who? => s.errTitleReach(who),
      null => s.errTitleReachNoSite,
    },
    _ when own => s.errTitleStudio(_toDo(e)),
    .rights => s.errTitleRights(_toDo(e)),
    .input => call == KnownCall.set ? s.errTitleInputValue : s.errTitleInput,
    .busy => s.errTitleBusy(e.site ?? s.errThingBroker, _noun(e)),
    .gone =>
      isUnsupported(e)
          ? s.errTitleUnsupported(_thing(e), e.call?.name ?? '')
          : s.errTitleGone(_thing(e)),
    .broker => switch (e.site) {
      final site? => s.errTitleBroker(_doing(e), site),
      null => s.errTitleBrokerNoSite(_doing(e)),
    },
  };
}

/// Handed to `createStore(wording:)`: gives [e] its title, and a fault in
/// Studio the sentence shown where a broker's message would be. A title or
/// a message that is there already is left alone.
StudioError wordError(StudioError e) => e.copyWith(
  title: e.title.isEmpty ? errorTitle(e) : e.title,
  message: e.message.isNotEmpty
      ? e.message
      : switch (e.hint) {
          final h? => _hintText(h),
          null when e.kind == .studio => S.current.errFaultMessage,
          null => e.message,
        },
);

/// What Studio says where the broker sent no words, or of what Studio
/// itself found wrong: one sentence per case, in the language on screen.
String _hintText(ErrorHint h) {
  final s = S.current;
  return switch (h) {
    ErrorHintRunDenied() => s.errRunDenied,
    ErrorHintRunNotRunning() => s.errRunNotRunning,
    ErrorHintRunNoTrigger() => s.errRunNoTrigger,
    ErrorHintRunNotByHand() => s.errRunNotByHand,
    ErrorHintNotSettable() => s.errNotSettable,
    ErrorHintNotConnected() => s.errNotConnected,
    ErrorHintNoAssistant() => s.errNoAssistant,
    ErrorHintAssistantNoTask() => s.errAssistantNoTask,
    ErrorHintAgentParamsUnread() => s.errAgentParamsUnread,
    ErrorHintTaskRecordInvalid(:final task, :final field, :final reason) =>
      s.errTaskRecordInvalid(task, field, reason),
    ErrorHintLibraryBlockInvalid(:final name, :final field, :final reason) =>
      s.errLibraryBlockInvalid(name, field, reason),
    ErrorHintFlowDefInvalid(:final flow, :final why) => s.errFlowDefInvalid(
      flow,
      why,
    ),
    ErrorHintNoEditAction() => s.errNoEditAction,
    ErrorHintProfileNotJson(:final detail) => s.errProfileNotJson(detail),
    ErrorHintProfileNotObject() => s.errProfileNotObject,
    ErrorHintProfileUnknownKey(:final key, :final known) =>
      s.errProfileUnknownKey(key, known.join(', ')),
    ErrorHintProfileUnknownType(:final type) => s.errProfileUnknownType(type),
    ErrorHintProfileTooBig() => s.errProfileTooBig,
    ErrorHintRangeBadText() => s.rangeBadText,
    ErrorHintRangeBadPart() => s.rangeBadPart,
    ErrorHintRangeBadPrefix() => s.rangeBadPrefix,
    ErrorHintRangeTooBig() => s.rangeTooBig,
    ErrorHintPortOutOfRange() => s.errPortOutOfRange,
    ErrorHintNoDeviceKey(:final host) => s.errNoDeviceKey(host.os.system),
    ErrorHintBackupNoDigest() => s.errBackupNoDigest,
    ErrorHintBackupDigestMismatch(:final got, :final expected) =>
      s.errBackupDigestMismatch(got, expected),
    ErrorHintFileEndedEarly(:final offset, :final size) => s.errFileEndedEarly(
      offset,
      size,
    ),
    ErrorHintEmptyPart() => s.errEmptyPart,
    ErrorHintSignCancelled() => s.errSignCancelled,
    ErrorHintSignLockedOut() => s.errSignLockedOut,
    ErrorHintSignKeyGone() => s.errSignKeyGone,
    ErrorHintSignUnavailable() => s.errSignUnavailable,
    ErrorHintPackageHasNoLink(:final name) => s.errPackageHasNoLink(name),
  };
}

/// The tone of a kind (errors.md §1).
Tone errorToneOf(ErrorKind kind) => switch (kind) {
  .rights || .reach => .warn,
  .input => .ember,
  .busy || .gone => .neutral,
  .broker || .studio => .bad,
};

String _iconOf(ErrorKind kind) => switch (kind) {
  .rights => 'err_rights',
  .reach => 'err_reach',
  .input => 'err_input',
  .busy => 'err_busy',
  .gone => 'err_gone',
  .broker => 'err_broker',
  .studio => 'err_studio',
};

/// What the main button of an error dialog does.
enum ErrorAction { ok, retry, form, refresh, log }

/// The main button of [e]'s dialog. [readOnly] is the dialog opened from
/// Problems: it repeats no write and counts nothing down.
ErrorAction errorPrimary(StudioError e, {bool readOnly = false}) {
  final canRetry = e.retry != null && !(readOnly && e.write);
  return switch (e.kind) {
    .rights || .studio => .ok,
    .reach || .busy => canRetry ? .retry : .ok,
    .input => .form,
    .gone => e.reload != null ? .refresh : .ok,
    .broker =>
      e.status == null && e.report == null && e.site == null ? .ok : .log,
  };
}

/// Seconds a `busy` dialog waits before it tries again by itself.
const busyWait = 4;

/// `11:52:06`.
String errorTime(DateTime? t) => t == null ? '' : Formats.clockSeconds(t);

/// `timeout: the device did not answer.`: the status and the broker's
/// message on one line (a toast, a Problems card).
String errorLine(StudioError e) {
  final s = S.current;
  final message = e.message.isNotEmpty
      ? e.message
      : e.kind == .reach && e.site != null
      ? s.errSilentReach(e.site!)
      : '';
  return switch (e.status) {
    final st? when message.isEmpty => st.name,
    final st? => s.errStatusLine(st.name, message),
    null => message,
  };
}

/// [e] as the dialog draws it. [user], [role] and [gateway] are who is
/// logged in where.
ErrorDialogVm errorDialogVm(
  StudioError e, {
  String? user,
  String? role,
  String? gateway,
  bool readOnly = false,
}) {
  final s = S.current;
  final primary = errorPrimary(e, readOnly: readOnly);
  final own = e.kind == .studio || (e.status == null && e.kind != .broker);
  final silent = e.message.isEmpty;
  final r = e.report;
  final time = e.at == null
      ? ''
      : s.errTimeLocal(Formats.dateTimeSeconds(e.at!));
  return ErrorDialogVm(
    tone: errorToneOf(e.kind),
    icon: _iconOf(e.kind),
    title: e.title.isEmpty ? errorTitle(e) : e.title,
    where: e.where,
    saidLabel: own
        ? s.errSaidStudio
        : silent && e.kind == .reach
        ? s.errSaidNoAnswer
        : s.errSaidBroker,
    said: !silent
        ? e.message
        : e.kind == .reach && e.site != null
        ? s.errSilentReach(e.site!)
        : e.status != null
        ? s.errSilentStatus(e.status!.name)
        : s.errFaultMessage,
    adviceLabel: s.errWhatYouCanDo,
    advice: switch (e.kind) {
      .rights => [
        s.errAdviceRights,
        if (role != null && role.isNotEmpty && e.site != null)
          s.errAdviceRightsRole(role, e.site!),
      ],
      .reach => [
        if (e.call == null && e.key == null)
          s.errAdviceReachLogin
        else
          s.errAdviceReach,
      ],
      .input => [
        switch (e.field) {
          final f? => s.errAdviceInputField(f),
          null => s.errAdviceInput,
        },
      ],
      .busy => [
        if (primary == .retry && !readOnly)
          s.errAdviceBusyAuto
        else
          s.errAdviceBusy,
      ],
      .gone => [
        if (isUnsupported(e)) s.errAdviceUnsupported else s.errAdviceGone,
      ],
      .broker => [
        if (e.status == null) s.errAdviceBrokerSaid,
        if (e.at case final t? when primary == .log)
          s.errAdviceBroker(Formats.clock(t)),
      ],
      .studio => [
        s.errAdviceStudio,
        if (r != null) s.errAdviceReport,
      ],
    },
    note: e.kind == .reach && e.write ? s.errWriteNote : null,
    detailsLabel: s.errDetails,
    chip: switch (e.status) {
      final st? => st.name,
      null => r == null ? e.kind.name : s.errChipStudio(r.type),
    },
    details: [
      if (e.status case final st?) ErrorRowVm(s.errRowStatus, statusLine(st)),
      if (r != null) ...[
        ErrorRowVm(s.errRowError, r.line),
        if (r.where.isNotEmpty) ErrorRowVm(s.errRowIn, r.where),
        if (r.screen case final sc?) ErrorRowVm(s.errRowScreen, sc),
      ] else ...[
        if (e.call?.name case final c? when c.isNotEmpty)
          ErrorRowVm(
            s.errRowCall,
            e.key == null ? c : s.errCallOn(c, e.key!),
          ),
        if (e.site case final site?) ErrorRowVm(s.errRowSite, site),
        if (user != null && user.isNotEmpty)
          ErrorRowVm(
            s.errRowAs,
            role == null || role.isEmpty ? user : s.errUserRole(user, role),
          ),
        if (gateway != null && gateway.isNotEmpty)
          ErrorRowVm(s.errRowGateway, gateway),
      ],
      if (r != null) ErrorRowVm(s.errRowStudio, studioAbout),
      if (time.isNotEmpty) ErrorRowVm(s.errRowTime, time),
      if (r != null) ErrorRowVm(s.errRowReport, s.errReportNote),
    ],
    detailsOpen: e.kind == .broker || e.kind == .studio,
    copy: r != null ? s.errCopyReport : s.errCopyDetails,
    secondary: switch (primary) {
      .ok when e.kind == .rights => s.errSeeAccess,
      .ok || .form => null,
      _ => s.closeLabel,
    },
    primary: switch (primary) {
      .ok => s.ok,
      .retry => s.errTryAgain,
      .form => s.errBackToForm,
      .refresh => s.errRefresh,
      .log => s.errOpenLog,
    },
    countdown: e.kind == .busy && primary == .retry && !readOnly
        ? (e.wait ?? busyWait)
        : null,
    countdownLabel: s.errTryAgainIn,
    close: s.closeLabel,
  );
}

/// [e] as a toast: a quiet failure, 8 s; one of a stream that is down
/// stays until the stream is back.
ToastVm errorToastVm(StudioError e) => ToastVm(
  id: e.id,
  tone: errorToneOf(e.kind),
  title: e.title,
  line: e.stream == null
      ? errorLine(e)
      : [
          if (e.message.isNotEmpty) e.message,
          S.current.toastStream,
        ].join(' '),
  details: true,
  retry: e.retry != null && !e.write,
  stays: switch (e.stream) {
    final site? => S.current.toastStays(site),
    null => null,
  },
);

/// [e] as a card of the Problems drawer.
ProblemVm problemVm(StudioError e) => ProblemVm(
  id: e.id,
  tone: errorToneOf(e.kind),
  title: e.title,
  time: errorTime(e.at),
  where: e.where,
  said: errorLine(e),
  retry: e.retry != null && !e.write,
  shown: e.shown,
);

/// Who and where, for *Copy details*.
final class DetailsContext {
  const DetailsContext({
    this.user,
    this.role,
    this.gateway,
    this.studio = '',
  });

  final String? user;
  final String? role;
  final String? gateway;

  /// `0.3.0 (macOS 15.1)`.
  final String studio;
}

/// The plain text of *Copy details* (errors.md §3): title, key › call,
/// status (code), message, site, user (role), gateway URL, time, Studio
/// version and OS, each under the label the dialog's Details row has. A
/// `StudioError` holds no value and no argument, so none can be copied;
/// the message and the report are [redact]ed. With [report], the Dart
/// type, first line and stack trace are added (*Copy report*).
String detailsText(
  StudioError e,
  DetailsContext ctx, {
  bool report = false,
}) {
  final s = S.current;
  final r = e.report;
  final role = ctx.role;
  final lines = <String>[
    e.title,
    if (e.where.isNotEmpty) e.where,
    if (e.status case final st?) s.errCopyLine(s.errRowStatus, statusLine(st)),
    if (e.message.isNotEmpty) s.errCopyLine(s.errRowMessage, redact(e.message)),
    if (e.site case final site?) s.errCopyLine(s.errRowSite, site),
    if (ctx.user case final u? when u.isNotEmpty)
      s.errCopyLine(
        s.errRowAs,
        role == null || role.isEmpty ? u : s.errUserRole(u, role),
      ),
    if (ctx.gateway case final g? when g.isNotEmpty)
      s.errCopyLine(s.errRowGateway, withoutUserInfo(g)),
    if (e.at case final t?)
      s.errCopyLine(
        s.errRowTime,
        s.errTimeLocal(Formats.dateTimeSeconds(t)),
      ),
    if (ctx.studio.isNotEmpty) s.errCopyLine(s.errRowStudio, ctx.studio),
    if (r != null) ...[
      s.errCopyLine(s.errRowError, r.line),
      if (r.where.isNotEmpty) s.errCopyLine(s.errRowIn, r.where),
      if (r.screen case final sc?) s.errCopyLine(s.errRowScreen, sc),
    ],
    if (report && r != null && r.stack.isNotEmpty) ...['', r.stack.trimRight()],
  ];
  return lines.join('\n');
}
