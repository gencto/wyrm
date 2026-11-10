import 'dart:io';

import 'package:business/wyrm/failures.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:localization/localization.dart';
import 'package:models/error_kind.dart';
import 'package:models/studio_error.dart';
import 'package:ui/alerts/toast_stack.dart';
import 'package:ui/dialogs/error_dialog.dart';
import 'package:ui/models/tone.dart';
import 'package:ui/overlays/problems_drawer.dart';

import 'connectors/log_in_page_connector.dart' show studioVersion;

// The words of an error (docs/design/specs/errors.md §1, §3, §7). They live
// in `app` because this is the only package that may name `S`: `business`
// keeps a failure as data (kind, status, call, key, thing, site) and asks
// for its words through `ErrorWording`.

/// `1.0 (macOS 15.1)`: Studio's version and the system it runs on.
String get studioAbout {
  if (kIsWeb) {
    return S.current.studioAbout(studioVersion, 'web');
  }
  final os = switch (Platform.operatingSystem) {
    'macos' => 'macOS',
    'windows' => 'Windows',
    'linux' => 'Linux',
    final o => o,
  };
  // `Version 15.1 (Build 24B83)` → `15.1`.
  final version = RegExp(
    r'\d+(\.\d+)+',
  ).firstMatch(Platform.operatingSystemVersion)?.group(0);
  return S.current.studioAbout(
    studioVersion,
    version == null ? os : '$os $version',
  );
}

enum _Verb {
  deploy,
  install,
  write,
  read,
  list,
  remove,
  save,
  start,
  stop,
  open,
  logIn,
  run,
}

_Verb _verbOf(String? call) => switch (call) {
  'deploy' => .deploy,
  'install' ||
  'install_repo' ||
  'install_zip' ||
  'install_url' ||
  'install_git' ||
  'install_wasm' => .install,
  'set' => .write,
  'list' => .list,
  'meta' ||
  'subscribe' ||
  'history' ||
  'get_log' ||
  'get_block' ||
  'get_def' ||
  'node_types' ||
  'tail' ||
  'users' ||
  'me' ||
  'read' => .read,
  'remove' || 'remove_user' || 'reject' => .remove,
  'put' ||
  'put_block' ||
  'edit' ||
  'update' ||
  'update_permissions' ||
  'save_user' ||
  'grant' ||
  'add' => .save,
  'start' => .start,
  'stop' => .stop,
  'open' => .open,
  'log_in' => .logIn,
  _ => .run,
};

/// The name of what [e] was about: given by the caller, else the last
/// segment of the key, else `this`.
String _thing(StudioError e) => switch (e.thing) {
  final t? when t.isNotEmpty => t,
  _ => switch (e.key?.split('/').last) {
    final k? when k.isNotEmpty && k != '**' => k,
    _ => e.site ?? S.current.errThingThis,
  },
};

/// `deploy pump-control`: after `You can’t` and `Studio could not`.
String _toDo(StudioError e) {
  final s = S.current;
  final t = _thing(e);
  return switch (_verbOf(e.call)) {
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
    .run => e.call == null ? s.errDoStep(t) : s.errDoRun(e.call!, t),
  };
}

/// `Installing modbus 0.4.2`: before `failed on plant`.
String _doing(StudioError e) {
  final s = S.current;
  final t = _thing(e);
  return switch (_verbOf(e.call)) {
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
    .run => s.errDoingRun(e.call ?? '', t),
  };
}

/// `the install`: before `did not start`.
String _noun(StudioError e) {
  final s = S.current;
  return switch (_verbOf(e.call)) {
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
    .run => s.errNounRun(e.call ?? ''),
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
  if (e.quiet && e.call == 'subscribe') {
    return s.errTitleRead(_thing(e));
  }
  if (e.call == 'history') {
    return s.errTitleHistory(_thing(e));
  }
  // Said by Studio, not by the broker: a file it cannot read, a fault.
  final own = e.status == null && e.kind != .broker;
  return switch (e.kind) {
    .studio =>
      e.report != null
          ? s.errTitleStudio(s.errDoStep(e.call ?? s.errThingThis))
          : e.call == null
          ? s.errTitlePlain
          : s.errTitleStudio(_toDo(e)),
    .reach when e.call == null && e.key == null => s.errTitleNotConnected,
    .reach when e.call == 'log_in' || e.call == 'me' => s.errTitleReach(
      _thing(e),
    ),
    .reach => switch (_unreached(e)) {
      final who? => s.errTitleReach(who),
      null => s.errTitleReachNoSite,
    },
    _ when own => s.errTitleStudio(_toDo(e)),
    .rights => s.errTitleRights(_toDo(e)),
    .input => e.call == 'set' ? s.errTitleInputValue : s.errTitleInput,
    .busy => s.errTitleBusy(e.site ?? s.errThingBroker, _noun(e)),
    .gone =>
      isUnsupported(e)
          ? s.errTitleUnsupported(_thing(e), e.call ?? '')
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
  message: e.message.isEmpty && e.kind == .studio
      ? S.current.errFaultMessage
      : e.message,
);

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

String _clock(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(t.hour)}:${two(t.minute)}';
}

/// `11:52:06`.
String errorTime(DateTime? t) {
  if (t == null) {
    return '';
  }
  String two(int v) => v.toString().padLeft(2, '0');
  return '${_clock(t)}:${two(t.second)}';
}

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
  final time = e.at == null ? '' : s.errTimeLocal(stamp(e.at!));
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
          s.errAdviceBroker(_clock(t)),
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
        if (e.call case final c? when c.isNotEmpty)
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
