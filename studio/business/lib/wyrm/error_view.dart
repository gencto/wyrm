import 'package:models/error_action.dart';
import 'package:models/error_hint.dart';
import 'package:models/error_kind.dart';
import 'package:models/error_title.dart';
import 'package:models/error_voice.dart';
import 'package:models/known_call.dart';
import 'package:models/studio_error.dart';

import 'failures.dart';

// What is decided of one failure (docs/design/specs/errors.md §1, §2, §7):
// which title it has, who is said to have spoken, what its dialog's main
// button does and how long it counts down. Decided here from the error as
// data; `ui` only says it (studio-rules §3).

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

  /// Nothing was said of it: no words of the broker's, of another
  /// package's, and no sentence of Studio's for the case.
  bool get silent =>
      message.isEmpty &&
      hint == null &&
      (foreign?.detail ?? '').isEmpty &&
      kind != ErrorKind.studio;

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

  /// Its dialog opens with Details shown: the broker's own failure and a
  /// fault in Studio are read there.
  bool get detailsOpen => kind == ErrorKind.broker || kind == ErrorKind.studio;

  /// A toast or a Problems card offers *Try again*: it can be repeated as
  /// it was, and repeats no write.
  bool get offersRetry => retry != null && !write;
}
