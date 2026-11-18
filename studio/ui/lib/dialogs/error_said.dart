import 'package:equatable/equatable.dart';
import 'package:localization/localization.dart';

import '../indicators/app_icon.dart';
import '../indicators/device_os.dart';
import '../models/tone.dart';
import 'error_dialog.dart';
import 'error_hint_words.dart';

// The words of an error (docs/design/specs/errors.md §1, §3, §7): one
// failure as typed values ([ErrorSaid]) and everything said of it — its
// title, its line, its dialog, its toast, its Problems card, the text of
// *Copy details* — in the language on screen when it is drawn.

/// What kind of failure it is: the kind picks the tone, the "what you can
/// do" lines and the main button.
enum ErrorKindTag {
  rights,
  reach,
  input,
  busy,
  gone,
  broker,
  studio;

  /// The tone of a kind (errors.md §1).
  Tone get tone => switch (this) {
    rights || reach => Tone.warn,
    input => Tone.ember,
    busy || gone => Tone.neutral,
    broker || studio => Tone.bad,
  };
}

/// What the failed call does, for the title's words.
enum ErrorVerb {
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

/// A call whose failure has a title of its own.
enum ErrorCallTag { subscribe, history, enableDevice, logIn, me, set }

/// The call an error is about: its [name] as it is written in *key › call*
/// (data), what it does, and whether it is one with words of its own.
final class ErrorCallVm extends Equatable {
  const ErrorCallVm(this.name, {this.verb = ErrorVerb.run, this.tag});

  final String name;
  final ErrorVerb verb;
  final ErrorCallTag? tag;

  @override
  List<Object?> get props => [name, verb, tag];
}

/// What the call was about: a thing Studio names itself, a name that came
/// as data, or nothing known.
sealed class ErrorThingVm extends Equatable {
  const ErrorThingVm();

  /// A name as it came: of a node, a flow, a package, a site.
  const factory ErrorThingVm.named(String name) = ErrorThingNamed;

  /// One of Studio's own nouns; [name] is the device's id for a device.
  const factory ErrorThingVm.own(ErrorNoun noun, [String name]) = ErrorThingOwn;

  /// Nothing is known of it: `this`.
  const factory ErrorThingVm.unnamed() = ErrorThingUnnamed;

  String get text;
}

final class ErrorThingNamed extends ErrorThingVm {
  const ErrorThingNamed(this.name);

  final String name;

  @override
  String get text => name;

  @override
  List<Object?> get props => [name];
}

/// The things an error can be about that Studio names itself.
enum ErrorNoun { assistant, profile, device, biometrics }

final class ErrorThingOwn extends ErrorThingVm {
  const ErrorThingOwn(this.noun, [this.name = '']);

  final ErrorNoun noun;
  final String name;

  @override
  String get text => switch (noun) {
    ErrorNoun.assistant => S.current.errThingAssistant,
    ErrorNoun.profile => S.current.errThingProfile,
    ErrorNoun.device => S.current.errThingDevice(name),
    ErrorNoun.biometrics => S.current.unlockNameBiometric,
  };

  @override
  List<Object?> get props => [noun, name];
}

final class ErrorThingUnnamed extends ErrorThingVm {
  const ErrorThingUnnamed();

  @override
  String get text => S.current.errThingThis;

  @override
  List<Object?> get props => const [];
}

/// A fault of Studio itself: what was thrown and where.
final class ErrorReportVm extends Equatable {
  const ErrorReportVm({
    required this.type,
    required this.line,
    this.where = '',
    this.screen,
    this.stack = '',
    this.uncaught = false,
  });

  final String type;
  final String line;
  final String where;
  final String? screen;
  final String stack;

  /// It came from outside any action: a fault in the background, or a
  /// panel ([screen]) that could not be drawn.
  final bool uncaught;

  @override
  List<Object?> get props => [type, line, where, screen, stack, uncaught];
}

/// Studio's version and the system it runs on: `1.0 (macOS 15.1)`.
final class StudioAbout extends Equatable {
  const StudioAbout({required this.version, required this.os, this.osVersion});

  final String version;
  final DeviceOs os;

  /// `15.1`; null when the system gives none.
  final String? osVersion;

  String get text => S.current.studioAbout(
    version,
    osVersion == null ? os.system : '${os.system} $osVersion',
  );

  @override
  List<Object?> get props => [version, os, osVersion];
}

/// Who is logged in where, and which Studio this is: for Details and
/// *Copy details*.
final class ErrorContext extends Equatable {
  const ErrorContext({this.user, this.role, this.gateway, this.about});

  final String? user;
  final String? role;

  /// The gateway's URL, without `user:password@`.
  final String? gateway;
  final StudioAbout? about;

  @override
  List<Object?> get props => [user, role, gateway, about];
}

/// What the main button of an error dialog does.
enum ErrorAction { ok, retry, form, refresh, log }

/// Seconds a `busy` dialog waits before it tries again by itself.
const busyWait = 4;

/// One failure, as typed values: what is known of it, none of it worded.
/// The getters word it in the language on screen.
final class ErrorSaid extends Equatable {
  const ErrorSaid({
    required this.id,
    required this.kind,
    required this.icon,
    required this.thing,
    this.givenTitle = '',
    this.message = '',
    this.hint,
    this.status,
    this.statusLine,
    this.timeout = false,
    this.unsupported = false,
    this.key,
    this.call,
    this.site,
    this.unreached,
    this.at,
    this.quiet = false,
    this.write = false,
    this.canRetry = false,
    this.canReload = false,
    this.field,
    this.report,
    this.shown = false,
    this.stream,
    this.wait,
  });

  final int id;
  final ErrorKindTag kind;
  final AppIcon icon;
  final ErrorThingVm thing;

  /// A title that came with the failure (another package's own); empty for
  /// one Studio words.
  final String givenTitle;

  /// The broker's words, as they came; empty when it sent none.
  final String message;

  /// What Studio says where there are no words of the broker's.
  final ErrorHintVm? hint;

  /// The status of the refusal by name (`timeout`); null for Studio's own
  /// faults and an answer that says no.
  final String? status;

  /// The status with its code: `permission_denied (0x21)`.
  final String? statusLine;

  /// The broker gave no answer in time.
  final bool timeout;

  /// The call is one this broker or link does not have.
  final bool unsupported;

  /// The full key the call was made on.
  final String? key;
  final ErrorCallVm? call;
  final String? site;

  /// Who did not answer: the site, or the link below it.
  final String? unreached;

  /// When it failed, local time.
  final DateTime? at;
  final bool quiet;

  /// The call changes something: a timeout may have been applied.
  final bool write;
  final bool canRetry;
  final bool canReload;

  /// The parameter an `invalid_parameter` names.
  final String? field;
  final ErrorReportVm? report;

  /// Opened as a dialog (the drawer says so).
  final bool shown;

  /// A live stream of this site went down.
  final String? stream;

  /// The seconds *Try again* waits for, when the broker gave a hint.
  final int? wait;

  /// `wy/plant/dataflows/pump-control › deploy`, or the part there is.
  String get where => [
    if (key case final k? when k.isNotEmpty) k,
    if (call?.name case final c? when c.isNotEmpty) c,
  ].join(' › ');

  ErrorVerb get _verb => call?.verb ?? ErrorVerb.run;

  /// `deploy pump-control`: after `You can’t` and `Studio could not`.
  String get _toDo {
    final s = S.current;
    final t = thing.text;
    return switch (_verb) {
      ErrorVerb.deploy => s.errDoDeploy(t),
      ErrorVerb.install => s.errDoInstall(t),
      ErrorVerb.write => s.errDoWrite(t),
      ErrorVerb.read => s.errDoRead(t),
      ErrorVerb.list => s.errDoList(t),
      ErrorVerb.remove => s.errDoRemove(t),
      ErrorVerb.save => s.errDoSave(t),
      ErrorVerb.start => s.errDoStart(t),
      ErrorVerb.stop => s.errDoStop(t),
      ErrorVerb.open => s.errDoOpen(t),
      ErrorVerb.logIn => s.errDoLogIn(t),
      ErrorVerb.run => switch (call) {
        final c? => s.errDoRun(c.name, t),
        null => s.errDoStep(t),
      },
    };
  }

  /// `Installing modbus 0.4.2`: before `failed on plant`.
  String get _doing {
    final s = S.current;
    final t = thing.text;
    return switch (_verb) {
      ErrorVerb.deploy => s.errDoingDeploy(t),
      ErrorVerb.install => s.errDoingInstall(t),
      ErrorVerb.write => s.errDoingWrite(t),
      ErrorVerb.read => s.errDoingRead(t),
      ErrorVerb.list => s.errDoingList(t),
      ErrorVerb.remove => s.errDoingRemove(t),
      ErrorVerb.save => s.errDoingSave(t),
      ErrorVerb.start => s.errDoingStart(t),
      ErrorVerb.stop => s.errDoingStop(t),
      ErrorVerb.open => s.errDoingOpen(t),
      ErrorVerb.logIn => s.errDoingLogIn(t),
      ErrorVerb.run => s.errDoingRun(call?.name ?? '', t),
    };
  }

  /// `the install`: before `did not start`.
  String get _noun {
    final s = S.current;
    return switch (_verb) {
      ErrorVerb.deploy => s.errNounDeploy,
      ErrorVerb.install => s.errNounInstall,
      ErrorVerb.write => s.errNounWrite,
      ErrorVerb.read => s.errNounRead,
      ErrorVerb.list => s.errNounList,
      ErrorVerb.remove => s.errNounRemove,
      ErrorVerb.save => s.errNounSave,
      ErrorVerb.start => s.errNounStart,
      ErrorVerb.stop => s.errNounStop,
      ErrorVerb.open => s.errNounOpen,
      ErrorVerb.logIn => s.errNounLogIn,
      ErrorVerb.run => s.errNounRun(call?.name ?? ''),
    };
  }

  /// Said by Studio, not by the broker: a file it cannot read, a fault.
  bool get _own => status == null && kind != ErrorKindTag.broker;

  /// The title: what did not happen, with its object (errors.md §7).
  /// Never `Error` or `Something went wrong`.
  String get title {
    if (givenTitle.isNotEmpty) {
      return givenTitle;
    }
    final s = S.current;
    // What Studio did on its own reads as what the user sees stop.
    if (stream case final site?) {
      return s.errTitleStream(site);
    }
    final tag = call?.tag;
    if (quiet && tag == ErrorCallTag.subscribe) {
      return s.errTitleRead(thing.text);
    }
    if (tag == ErrorCallTag.history) {
      return s.errTitleHistory(thing.text);
    }
    // The offer's `Use <name>` or the Security switch (unlock-discover.md
    // §2): `Touch ID could not be turned on`, the reason under it.
    if (tag == ErrorCallTag.enableDevice) {
      return s.unlockOffToast(thing.text);
    }
    if (report case ErrorReportVm(uncaught: true, :final screen)) {
      return screen == null ? s.faultUncaught : s.faultProblem(screen);
    }
    return switch (kind) {
      ErrorKindTag.studio =>
        report != null
            ? s.errTitleStudio(s.errDoStep(call?.name ?? s.errThingThis))
            : call == null
            ? s.errTitlePlain
            : s.errTitleStudio(_toDo),
      ErrorKindTag.reach when call == null && key == null =>
        s.errTitleNotConnected,
      ErrorKindTag.reach
          when tag == ErrorCallTag.logIn || tag == ErrorCallTag.me =>
        s.errTitleReach(thing.text),
      ErrorKindTag.reach => switch (unreached) {
        final who? => s.errTitleReach(who),
        null => s.errTitleReachNoSite,
      },
      _ when _own => s.errTitleStudio(_toDo),
      ErrorKindTag.rights => s.errTitleRights(_toDo),
      ErrorKindTag.input =>
        tag == ErrorCallTag.set ? s.errTitleInputValue : s.errTitleInput,
      ErrorKindTag.busy => s.errTitleBusy(site ?? s.errThingBroker, _noun),
      ErrorKindTag.gone =>
        unsupported
            ? s.errTitleUnsupported(thing.text, call?.name ?? '')
            : s.errTitleGone(thing.text),
      ErrorKindTag.broker => switch (site) {
        final site? => s.errTitleBroker(_doing, site),
        null => s.errTitleBrokerNoSite(_doing),
      },
    };
  }

  /// What was said of it: the broker's words as they came; else Studio's
  /// sentence for the case; for a fault in Studio the sentence shown where
  /// a broker's message would be; else nothing.
  String get said => message.isNotEmpty
      ? message
      : switch (hint) {
          final h? => h.text,
          null when kind == ErrorKindTag.studio => S.current.errFaultMessage,
          null => '',
        };

  /// `timeout: the device did not answer.`: the status and what was said
  /// on one line (a toast, a Problems card).
  String get line {
    final s = S.current;
    final words = said;
    final message = words.isNotEmpty
        ? words
        : kind == ErrorKindTag.reach && site != null
        ? s.errSilentReach(site!)
        : '';
    return switch (status) {
      final st? when message.isEmpty => st,
      final st? => s.errStatusLine(st, message),
      null => message,
    };
  }

  /// The main button of its dialog. [readOnly] is the dialog opened from
  /// Problems: it repeats no write and counts nothing down.
  ErrorAction primary({bool readOnly = false}) {
    final retries = canRetry && !(readOnly && write);
    return switch (kind) {
      ErrorKindTag.rights || ErrorKindTag.studio => ErrorAction.ok,
      ErrorKindTag.reach ||
      ErrorKindTag.busy => retries ? ErrorAction.retry : ErrorAction.ok,
      ErrorKindTag.input => ErrorAction.form,
      ErrorKindTag.gone => canReload ? ErrorAction.refresh : ErrorAction.ok,
      ErrorKindTag.broker =>
        status == null && report == null && site == null
            ? ErrorAction.ok
            : ErrorAction.log,
    };
  }

  String _as(String user, String? role) =>
      role == null || role.isEmpty ? user : S.current.errUserRole(user, role);

  /// It as the dialog draws it, for who is logged in where ([ctx]).
  ErrorDialogVm dialog(ErrorContext ctx, {bool readOnly = false}) {
    final s = S.current;
    final main = primary(readOnly: readOnly);
    final own = kind == ErrorKindTag.studio || _own;
    final words = said;
    final silent = words.isEmpty;
    final r = report;
    final role = ctx.role;
    return ErrorDialogVm(
      tone: kind.tone,
      icon: icon,
      title: title,
      where: where,
      saidLabel: own
          ? s.errSaidStudio
          : silent && kind == ErrorKindTag.reach
          ? s.errSaidNoAnswer
          : s.errSaidBroker,
      said: !silent
          ? words
          : kind == ErrorKindTag.reach && site != null
          ? s.errSilentReach(site!)
          : status != null
          ? s.errSilentStatus(status!)
          : s.errFaultMessage,
      adviceLabel: s.errWhatYouCanDo,
      advice: switch (kind) {
        ErrorKindTag.rights => [
          s.errAdviceRights,
          if (role != null && role.isNotEmpty && site != null)
            s.errAdviceRightsRole(role, site!),
        ],
        ErrorKindTag.reach => [
          if (call == null && key == null)
            s.errAdviceReachLogin
          else
            s.errAdviceReach,
        ],
        ErrorKindTag.input => [
          switch (field) {
            final f? => s.errAdviceInputField(f),
            null => s.errAdviceInput,
          },
        ],
        ErrorKindTag.busy => [
          if (main == ErrorAction.retry && !readOnly)
            s.errAdviceBusyAuto
          else
            s.errAdviceBusy,
        ],
        ErrorKindTag.gone => [
          if (unsupported) s.errAdviceUnsupported else s.errAdviceGone,
        ],
        ErrorKindTag.broker => [
          if (status == null) s.errAdviceBrokerSaid,
          if (at case final t? when main == ErrorAction.log)
            s.errAdviceBroker(Formats.clock(t)),
        ],
        ErrorKindTag.studio => [
          s.errAdviceStudio,
          if (r != null) s.errAdviceReport,
        ],
      },
      note: kind == ErrorKindTag.reach && write ? s.errWriteNote : null,
      detailsLabel: s.errDetails,
      chip: switch (status) {
        final st? => st,
        null => r == null ? kind.name : s.errChipStudio(r.type),
      },
      details: [
        if (statusLine case final st?) ErrorRowVm(s.errRowStatus, st),
        if (r != null) ...[
          ErrorRowVm(s.errRowError, r.line),
          if (r.where.isNotEmpty) ErrorRowVm(s.errRowIn, r.where),
          if (r.screen case final sc?) ErrorRowVm(s.errRowScreen, sc),
        ] else ...[
          if (call?.name case final c? when c.isNotEmpty)
            ErrorRowVm(s.errRowCall, key == null ? c : s.errCallOn(c, key!)),
          if (site case final site?) ErrorRowVm(s.errRowSite, site),
          if (ctx.user case final user? when user.isNotEmpty)
            ErrorRowVm(s.errRowAs, _as(user, role)),
          if (ctx.gateway case final g? when g.isNotEmpty)
            ErrorRowVm(s.errRowGateway, g),
        ],
        if (ctx.about case final about? when r != null)
          ErrorRowVm(s.errRowStudio, about.text),
        if (at case final t?)
          ErrorRowVm(
            s.errRowTime,
            s.errTimeLocal(Formats.dateTimeSeconds(t)),
          ),
        if (r != null) ErrorRowVm(s.errRowReport, s.errReportNote),
      ],
      detailsOpen: kind == ErrorKindTag.broker || kind == ErrorKindTag.studio,
      copy: r != null ? s.errCopyReport : s.errCopyDetails,
      secondary: switch (main) {
        ErrorAction.ok when kind == ErrorKindTag.rights => s.errSeeAccess,
        ErrorAction.ok || ErrorAction.form => null,
        _ => s.closeLabel,
      },
      primary: switch (main) {
        ErrorAction.ok => s.ok,
        ErrorAction.retry => s.errTryAgain,
        ErrorAction.form => s.errBackToForm,
        ErrorAction.refresh => s.errRefresh,
        ErrorAction.log => s.errOpenLog,
      },
      countdown:
          kind == ErrorKindTag.busy && main == ErrorAction.retry && !readOnly
          ? (wait ?? busyWait)
          : null,
      countdownLabel: s.errTryAgainIn,
      close: s.closeLabel,
    );
  }

  /// The line of its toast: [line]; for a stream that is down what was
  /// said and that Studio reopens it.
  String get toastLine {
    if (stream == null) {
      return line;
    }
    final words = said;
    return [if (words.isNotEmpty) words, S.current.toastStream].join(' ');
  }

  /// `11:52:06`: when it failed; empty when that is not known.
  String get time => switch (at) {
    final t? => Formats.clockSeconds(t),
    null => '',
  };

  /// The plain text of *Copy details* (errors.md §3): title, key › call,
  /// status (code), what was said, site, user (role), gateway URL, time,
  /// Studio's version and system, each under the label its Details row
  /// has. An error holds no value and no argument, so none can be copied;
  /// what was said goes through [redact] (the caller's: what looks like a
  /// secret is masked). With [report], the stack trace is added (*Copy
  /// report*).
  String details(
    ErrorContext ctx, {
    required String Function(String text) redact,
    bool report = false,
  }) {
    final s = S.current;
    final r = this.report;
    final words = said;
    final lines = <String>[
      title,
      if (where.isNotEmpty) where,
      if (statusLine case final st?) s.errCopyLine(s.errRowStatus, st),
      if (words.isNotEmpty) s.errCopyLine(s.errRowMessage, redact(words)),
      if (site case final site?) s.errCopyLine(s.errRowSite, site),
      if (ctx.user case final u? when u.isNotEmpty)
        s.errCopyLine(s.errRowAs, _as(u, ctx.role)),
      if (ctx.gateway case final g? when g.isNotEmpty)
        s.errCopyLine(s.errRowGateway, g),
      if (at case final t?)
        s.errCopyLine(
          s.errRowTime,
          s.errTimeLocal(Formats.dateTimeSeconds(t)),
        ),
      if (ctx.about case final about?)
        s.errCopyLine(s.errRowStudio, about.text),
      if (r != null) ...[
        s.errCopyLine(s.errRowError, r.line),
        if (r.where.isNotEmpty) s.errCopyLine(s.errRowIn, r.where),
        if (r.screen case final sc?) s.errCopyLine(s.errRowScreen, sc),
      ],
      if (report && r != null && r.stack.isNotEmpty) ...[
        '',
        r.stack.trimRight(),
      ],
    ];
    return lines.join('\n');
  }

  @override
  List<Object?> get props => [
    id,
    kind,
    icon,
    thing,
    givenTitle,
    message,
    hint,
    status,
    statusLine,
    timeout,
    unsupported,
    key,
    call,
    site,
    unreached,
    at,
    quiet,
    write,
    canRetry,
    canReload,
    field,
    report,
    shown,
    stream,
    wait,
  ];
}
