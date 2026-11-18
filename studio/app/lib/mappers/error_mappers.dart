import 'package:business/wyrm/device_keys.dart' show hostPlatform;
import 'package:business/wyrm/error_view.dart';
import 'package:business/wyrm/failures.dart';
import 'package:business/wyrm/keys.dart';
import 'package:models/call_verb.dart';
import 'package:models/error_action.dart';
import 'package:models/error_call.dart';
import 'package:models/error_hint.dart';
import 'package:models/error_kind.dart';
import 'package:models/error_subject.dart';
import 'package:models/error_title.dart';
import 'package:models/error_voice.dart';
import 'package:models/fault_report.dart';
import 'package:models/studio_error.dart';
import 'package:ui/alerts/toast_stack.dart';
import 'package:ui/dialogs/error_dialog.dart';
import 'package:ui/dialogs/error_hint_words.dart';
import 'package:ui/dialogs/error_said.dart';
import 'package:ui/overlays/problems_drawer.dart';

import '../common/studio_version.dart';
import 'device_mappers.dart';
import 'icon_mappers.dart';
import 'log_in_mappers.dart';

// One failure as `ui` words it (studio-rules §3, §5): the domain's
// `StudioError` as typed values, one exhaustive switch per domain type.
// Nothing here is a word: `ui/lib/dialogs/error_said.dart` says the title,
// the line, the dialog, the toast and *Copy details*.

/// Studio's version and the system it runs on, for Details.
StudioAbout get studioAbout => StudioAbout(
  version: studioVersion,
  os: hostPlatform().os,
  osVersion: hostOsVersion(),
);

extension ErrorKindTagOf on ErrorKind {
  ErrorKindTag get tag => switch (this) {
    ErrorKind.rights => .rights,
    ErrorKind.reach => .reach,
    ErrorKind.input => .input,
    ErrorKind.busy => .busy,
    ErrorKind.gone => .gone,
    ErrorKind.broker => .broker,
    ErrorKind.studio => .studio,
  };
}

extension ErrorButtonOf on ErrorAction {
  ErrorButton get button => switch (this) {
    ErrorAction.ok => .ok,
    ErrorAction.retry => .retry,
    ErrorAction.form => .form,
    ErrorAction.refresh => .refresh,
    ErrorAction.log => .log,
  };
}

extension ErrorTitleTagOf on ErrorTitle {
  ErrorTitleTag get tag => switch (this) {
    ErrorTitle.foreign => .foreign,
    ErrorTitle.startFault => .startFault,
    ErrorTitle.stream => .stream,
    ErrorTitle.readFailed => .readFailed,
    ErrorTitle.history => .history,
    ErrorTitle.deviceOff => .deviceOff,
    ErrorTitle.uncaughtBackground => .uncaughtBackground,
    ErrorTitle.uncaughtPanel => .uncaughtPanel,
    ErrorTitle.studioStep => .studioStep,
    ErrorTitle.plain => .plain,
    ErrorTitle.studioCould => .studioCould,
    ErrorTitle.notConnected => .notConnected,
    ErrorTitle.reachThing => .reachThing,
    ErrorTitle.reachWho => .reachWho,
    ErrorTitle.reachNoSite => .reachNoSite,
    ErrorTitle.rights => .rights,
    ErrorTitle.inputValue => .inputValue,
    ErrorTitle.input => .input,
    ErrorTitle.busy => .busy,
    ErrorTitle.unsupported => .unsupported,
    ErrorTitle.gone => .gone,
    ErrorTitle.broker => .broker,
  };
}

extension ErrorVoiceTagOf on ErrorVoice {
  ErrorVoiceTag get tag => switch (this) {
    ErrorVoice.studio => .studio,
    ErrorVoice.noAnswer => .noAnswer,
    ErrorVoice.broker => .broker,
  };
}

extension CallVerbOf on CallVerb {
  ErrorVerb get vm => switch (this) {
    CallVerb.deploy => .deploy,
    CallVerb.install => .install,
    CallVerb.write => .write,
    CallVerb.read => .read,
    CallVerb.list => .list,
    CallVerb.remove => .remove,
    CallVerb.save => .save,
    CallVerb.start => .start,
    CallVerb.stop => .stop,
    CallVerb.open => .open,
    CallVerb.logIn => .logIn,
    CallVerb.run => .run,
  };
}

extension ErrorCallVmOf on ErrorCall {
  /// The call with its name and what it does.
  ErrorCallVm get vm => ErrorCallVm(name, verb: verb.vm);
}

extension ErrorHintVmOf on ErrorHint {
  ErrorHintVm get vm => switch (this) {
    ErrorHintRunDenied() => const .tag(.runDenied),
    ErrorHintRunNotRunning() => const .tag(.runNotRunning),
    ErrorHintRunNoTrigger() => const .tag(.runNoTrigger),
    ErrorHintRunNotByHand() => const .tag(.runNotByHand),
    ErrorHintNotSettable() => const .tag(.notSettable),
    ErrorHintNotConnected() => const .tag(.notConnected),
    ErrorHintNoAssistant() => const .tag(.noAssistant),
    ErrorHintAssistantNoTask() => const .tag(.assistantNoTask),
    ErrorHintAgentParamsUnread() => const .tag(.agentParamsUnread),
    ErrorHintTaskRecordInvalid(:final task, :final field) => .unreadable(
      .taskRecord,
      name: task,
      field: field,
    ),
    ErrorHintLibraryBlockInvalid(:final name, :final field) => .unreadable(
      .libraryBlock,
      name: name,
      field: field,
    ),
    ErrorHintFlowDefInvalid(:final flow, :final field) => .unreadable(
      .flowDef,
      name: flow,
      field: field,
    ),
    ErrorHintNoEditAction() => const .tag(.noEditAction),
    ErrorHintProfileNotJson(:final detail) => .profileNotJson(detail),
    ErrorHintProfileNotObject() => const .tag(.profileNotObject),
    ErrorHintProfileUnknownKey(:final key, :final known) => .profileUnknownKey(
      key,
      known.unlockView,
    ),
    ErrorHintProfileUnknownType(:final type) => .profileUnknownType(type),
    ErrorHintProfileTooBig() => const .tag(.profileTooBig),
    ErrorHintRangeBadText() => const .tag(.rangeBadText),
    ErrorHintRangeBadPart() => const .tag(.rangeBadPart),
    ErrorHintRangeBadPrefix() => const .tag(.rangeBadPrefix),
    ErrorHintRangeTooBig() => const .tag(.rangeTooBig),
    ErrorHintPortOutOfRange() => const .tag(.portOutOfRange),
    ErrorHintNoAnswer(:final why) => .noAnswer(why.view),
    ErrorHintNoDeviceKey(:final host) => .noDeviceKey(host.os),
    ErrorHintFileEndedEarly(:final offset, :final size) => .fileEndedEarly(
      offset,
      size,
    ),
    ErrorHintSignCancelled() => const .tag(.signCancelled),
    ErrorHintSignLockedOut() => const .tag(.signLockedOut),
    ErrorHintSignKeyGone() => const .tag(.signKeyGone),
    ErrorHintSignUnavailable() => const .tag(.signUnavailable),
    ErrorHintPackageHasNoLink(:final name) => .packageHasNoLink(name),
    ErrorHintEmptyPart() => const .tag(.emptyPart),
    ErrorHintSettingsUnreadable() => const .tag(.settingsUnreadable),
  };
}

extension FaultReportVmOf on FaultReport {
  ErrorReportVm get vm => ErrorReportVm(
    type: type,
    line: line,
    where: where,
    screen: screen,
    stack: stack,
    uncaught: uncaught,
  );
}

extension ErrorSaidOf on StudioError {
  /// What the call was about: a thing Studio names itself, else the name
  /// given by the caller, else the node its key names, else the site.
  ErrorThingVm get _thing => switch (subject) {
    ErrorSubject.assistant => const .own(.assistant),
    ErrorSubject.profile => const .own(.profile),
    ErrorSubject.device => .own(.device, thing ?? ''),
    ErrorSubject.biometrics => const .own(.biometrics),
    null => switch (thing) {
      final t? when t.isNotEmpty => .named(t),
      _ => switch (lastNameOf(key) ?? site) {
        final name? => .named(name),
        null => const .unnamed(),
      },
    },
  };

  /// Its dialog, for who is logged in where ([ctx]): the main button and
  /// the countdown as `business` decides them. [readOnly] is the dialog
  /// opened from Problems.
  ErrorDialogVm dialog(ErrorContext ctx, {bool readOnly = false}) =>
      said.dialog(
        ctx,
        button: action(readOnly: readOnly).button,
        countdown: countdown(readOnly: readOnly),
      );

  /// The failure as typed values `ui` words when it draws it.
  ErrorSaid get said => ErrorSaid(
    id: id,
    kind: kind.tag,
    icon: kind.icon,
    thing: _thing,
    titleKind: titleKind.tag,
    voice: voice.tag,
    foreign: switch (foreign) {
      final f? => ErrorForeignVm(f.title, f.detail),
      null => null,
    },
    message: message,
    hint: hint?.vm,
    status: status?.name,
    statusLine: switch (status) {
      final st? => statusLine(st),
      null => null,
    },
    timeout: isTimeout(this),
    unsupported: isUnsupported(this),
    key: key,
    call: call?.vm,
    site: site,
    unreached: unreachedOf(this),
    at: at,
    quiet: quiet,
    write: write,
    offersRetry: offersRetry,
    detailsOpen: detailsOpen,
    field: field,
    report: report?.vm,
    shown: shown,
    stream: stream,
  );
}

extension ErrorDrawnOf on StudioError {
  /// The failure as a toast: `ui` words it when it draws it.
  ToastVm get toast => ToastVm.failure(said);

  /// The failure as a card of the Problems drawer.
  ProblemVm get problem => ProblemVm.failure(said);
}
