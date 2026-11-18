import 'package:models/error_action.dart';
import 'package:models/error_advice.dart';
import 'package:models/error_chip.dart';
import 'package:models/error_hint.dart';
import 'package:models/error_kind.dart';
import 'package:models/error_saying.dart';
import 'package:models/error_secondary.dart';
import 'package:models/error_title.dart';
import 'package:models/error_voice.dart';
import 'package:models/known_call.dart';
import 'package:models/studio_error.dart';

import 'failures.dart';

// What is decided of one failure (docs/design/specs/errors.md §1, §2, §7):
// which title it has, what its words are, who is said to have spoken, what
// its dialog advises, what its buttons do and how long it counts down, and
// what its chip shows. Decided here from the error as data; `ui` only says
// it (studio-rules §3).

/// Seconds a `busy` dialog waits before it tries again by itself.
const busyWait = 4;

/// The decisions over one [StudioError].
extension ErrorView on StudioError {
  /// Said by Studio, not by the broker: a file it cannot read, a fault.
  bool get _own => status == null && kind != ErrorKind.broker;

  /// Which title it has (errors.md §7): what did not happen, with its
  /// object. Never `Error` or `Something went wrong`.
  ErrorTitle get titleKind {
    if (foreign != null) {
      return ErrorTitle.foreign;
    }
    if (hint is ErrorHintSettingsUnreadable) {
      return ErrorTitle.startFault;
    }
    // What Studio did on its own reads as what the user sees stop.
    if (stream != null) {
      return ErrorTitle.stream;
    }
    final known = call?.known;
    if (quiet && known == KnownCall.subscribe) {
      return ErrorTitle.readFailed;
    }
    if (known == KnownCall.history) {
      return ErrorTitle.history;
    }
    // The offer's `Use <name>` or the Security switch (unlock-discover.md
    // §2): `Touch ID could not be turned on`, the reason under it.
    if (known == KnownCall.enableDevice) {
      return ErrorTitle.deviceOff;
    }
    if (report case final r? when r.uncaught) {
      return r.screen == null
          ? ErrorTitle.uncaughtBackground
          : ErrorTitle.uncaughtPanel;
    }
    return switch (kind) {
      ErrorKind.studio =>
        report != null
            ? ErrorTitle.studioStep
            : call == null
            ? ErrorTitle.plain
            : ErrorTitle.studioCould,
      ErrorKind.reach when call == null && key == null =>
        ErrorTitle.notConnected,
      ErrorKind.reach when known == KnownCall.logIn || known == KnownCall.me =>
        ErrorTitle.reachThing,
      ErrorKind.reach =>
        unreachedOf(this) == null
            ? ErrorTitle.reachNoSite
            : ErrorTitle.reachWho,
      _ when _own => ErrorTitle.studioCould,
      ErrorKind.rights => ErrorTitle.rights,
      ErrorKind.input =>
        known == KnownCall.set ? ErrorTitle.inputValue : ErrorTitle.input,
      ErrorKind.busy => ErrorTitle.busy,
      ErrorKind.gone =>
        isUnsupported(this) ? ErrorTitle.unsupported : ErrorTitle.gone,
      ErrorKind.broker => ErrorTitle.broker,
    };
  }

  /// What its words are: the broker's as they came, else another
  /// package's detail, else Studio's sentence for the case, else the
  /// sentence of a fault in Studio. With none of them: a site that did not
  /// answer, a status that came alone, or nothing at all.
  ErrorSaying get saying {
    if (message.isNotEmpty) {
      return ErrorSaying.broker;
    }
    if ((foreign?.detail ?? '').isNotEmpty) {
      return ErrorSaying.foreign;
    }
    if (hint != null) {
      return ErrorSaying.hint;
    }
    if (kind == ErrorKind.studio) {
      return ErrorSaying.fault;
    }
    if (kind == ErrorKind.reach && site != null) {
      return ErrorSaying.silentReach;
    }
    return status != null ? ErrorSaying.silentStatus : ErrorSaying.nothing;
  }

  /// Nothing was said of it: no words of the broker's, of another
  /// package's, and no sentence of Studio's for the case.
  bool get silent => switch (saying) {
    ErrorSaying.broker ||
    ErrorSaying.foreign ||
    ErrorSaying.hint ||
    ErrorSaying.fault => false,
    ErrorSaying.silentReach ||
    ErrorSaying.silentStatus ||
    ErrorSaying.nothing => true,
  };

  /// Who is said to have spoken: Studio of what it found itself, nobody
  /// when a call that did not reach was not answered, else the broker.
  ErrorVoice get voice => kind == ErrorKind.studio || _own
      ? ErrorVoice.studio
      : silent && kind == ErrorKind.reach
      ? ErrorVoice.noAnswer
      : ErrorVoice.broker;

  /// What the main button of its dialog does. [readOnly] is the dialog
  /// opened from Problems: it repeats no write.
  ErrorAction action({bool readOnly = false}) {
    final retries = retry != null && !(readOnly && write);
    return switch (kind) {
      ErrorKind.rights || ErrorKind.studio => ErrorAction.ok,
      ErrorKind.reach ||
      ErrorKind.busy => retries ? ErrorAction.retry : ErrorAction.ok,
      ErrorKind.input => ErrorAction.form,
      ErrorKind.gone => reload != null ? ErrorAction.refresh : ErrorAction.ok,
      ErrorKind.broker =>
        status == null && report == null && site == null
            ? ErrorAction.ok
            : ErrorAction.log,
    };
  }

  /// The seconds its dialog counts down before it tries again by itself:
  /// a `busy` that can be tried again, with the broker's hint or
  /// [busyWait]. Null when it does not; never from Problems ([readOnly]).
  int? countdown({bool readOnly = false}) =>
      kind == ErrorKind.busy &&
          !readOnly &&
          action(readOnly: readOnly) == ErrorAction.retry
      ? (wait ?? busyWait)
      : null;

  /// The lines under *What you can do* of its dialog, in their order.
  /// [role] is the role of who is logged in (a `rights` failure names it
  /// with the site); [readOnly] is the dialog opened from Problems.
  List<ErrorAdvice> advice({String? role, bool readOnly = false}) =>
      switch (kind) {
        ErrorKind.rights => [
          ErrorAdvice.rights,
          if (role != null && role.isNotEmpty && site != null)
            ErrorAdvice.rightsRole,
        ],
        ErrorKind.reach => [
          if (call == null && key == null)
            ErrorAdvice.reachLogin
          else
            ErrorAdvice.reach,
        ],
        ErrorKind.input => [
          if (field != null) ErrorAdvice.inputField else ErrorAdvice.input,
        ],
        ErrorKind.busy => [
          if (countdown(readOnly: readOnly) != null)
            ErrorAdvice.busyAuto
          else
            ErrorAdvice.busy,
        ],
        ErrorKind.gone => [
          if (isUnsupported(this))
            ErrorAdvice.unsupported
          else
            ErrorAdvice.gone,
        ],
        ErrorKind.broker => [
          if (status == null) ErrorAdvice.brokerSaid,
          if (at != null && action(readOnly: readOnly) == ErrorAction.log)
            ErrorAdvice.brokerLog,
        ],
        ErrorKind.studio => [
          ErrorAdvice.studio,
          if (report != null) ErrorAdvice.report,
        ],
      };

  /// Its dialog says that a write may have been applied: a call that
  /// changes something did not get its answer.
  bool get writeNote => kind == ErrorKind.reach && write;

  /// The second button of its dialog, beside the main one ([action]):
  /// *See access* for a refusal of rights, *Close* beside a button that
  /// does something, none beside OK or *Back to the form*.
  ErrorSecondary secondary({bool readOnly = false}) => switch (action(
    readOnly: readOnly,
  )) {
    ErrorAction.ok when kind == ErrorKind.rights => ErrorSecondary.seeAccess,
    ErrorAction.ok || ErrorAction.form => ErrorSecondary.none,
    ErrorAction.retry ||
    ErrorAction.refresh ||
    ErrorAction.log => ErrorSecondary.close,
  };

  /// What its chip shows: the status by name, else its kind, else for a
  /// fault in Studio what was thrown.
  ErrorChip get chip => status != null
      ? ErrorChip.status
      : report == null
      ? ErrorChip.kind
      : ErrorChip.studio;

  /// Its dialog opens with Details shown: the broker's own failure and a
  /// fault in Studio are read there.
  bool get detailsOpen => kind == ErrorKind.broker || kind == ErrorKind.studio;

  /// A toast or a Problems card offers *Try again*: it can be repeated as
  /// it was, and repeats no write.
  bool get offersRetry => retry != null && !write;
}
