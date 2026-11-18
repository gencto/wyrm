import 'package:freezed_annotation/freezed_annotation.dart';

import 'answer_fault.dart';
import 'host_platform.dart';
import 'manifest_problem.dart';
import 'unreadable_part.dart';

part 'error_hint.freezed.dart';

/// What Studio itself knows of why something did not happen, when the
/// words are Studio's and not the broker's (docs/design/specs/errors.md:
/// the broker's message is shown as it came). `business` names the case
/// with what it is about; the app says it in the user's language. A case
/// carries data only (a name, a key, a number, a decoder's field), never a
/// sentence.
@freezed
sealed class ErrorHint with _$ErrorHint {
  /// `trigger` refused for rights: it needs write on the flow and the
  /// rights of what the block and the blocks after it act on.
  const factory ErrorHint.runDenied() = ErrorHintRunDenied;

  /// `trigger` on a flow that is not running.
  const factory ErrorHint.runNotRunning() = ErrorHintRunNotRunning;

  /// The broker has no `trigger` action (ADR 0040).
  const factory ErrorHint.runNoTrigger() = ErrorHintRunNoTrigger;

  /// The block is not one that runs by hand.
  const factory ErrorHint.runNotByHand() = ErrorHintRunNotByHand;

  /// A value whose meta names no level it can be set at: Studio stages no
  /// set of it (the link would answer `not_supported`, not writable).
  const factory ErrorHint.notSettable() = ErrorHintNotSettable;

  /// Nobody is logged in: there is no gateway to ask.
  const factory ErrorHint.notConnected() = ErrorHintNotConnected;

  /// The site has no assistant link.
  const factory ErrorHint.noAssistant() = ErrorHintNoAssistant;

  /// The assistant's stream ended without naming a task (an agent without
  /// its API key does this).
  const factory ErrorHint.assistantNoTask() = ErrorHintAssistantNoTask;

  /// The agent link's parameters did not read, so no edit was staged.
  const factory ErrorHint.agentParamsUnread() = ErrorHintAgentParamsUnread;

  /// The broker answered, and what came is not of the shape it has, so
  /// Studio reads nothing out of it ([part]): an answer of a call, some
  /// entries of a list (their names are the error's `thing`; the others
  /// are shown), the record of task [name], the library block [name], the
  /// definition of flow [name]. [field] is the one that does not read, by
  /// its wire name (empty: only the log names it). Why it does not read is
  /// the decoder's and goes to the log, never to the screen.
  const factory ErrorHint.unreadable(
    UnreadablePart part, {
    @Default('') String name,
    @Default('') String field,
  }) = ErrorHintUnreadable;

  /// The node has no `edit` action.
  const factory ErrorHint.noEditAction() = ErrorHintNoEditAction;

  /// A file the user picked is not of the form its kind has (a profile
  /// that is no profile): nothing of it was sent. [problem] says which
  /// field or which name, and where the JSON stops.
  const factory ErrorHint.fileNotRead(ManifestProblem problem) =
      ErrorHintFileNotRead;

  /// The broker shows no SHA-256 of a backup: what arrives cannot be
  /// checked, so nothing was downloaded.
  const factory ErrorHint.backupNoDigest() = ErrorHintBackupNoDigest;

  /// The file that arrived is not the backup: its SHA-256 is not the one
  /// the broker shows (both are in the log). Nothing was saved.
  const factory ErrorHint.backupDigestMismatch() =
      ErrorHintBackupDigestMismatch;

  /// The check of a file brought for a link could not be run, or found
  /// nothing: the install does not go on.
  const factory ErrorHint.checkNotRun() = ErrorHintCheckNotRun;

  /// A step was started that its own plan blocks (a restore of another
  /// site's backup, keys not confirmed, no connection chosen): nothing
  /// was sent. The dialog names what is missing.
  const factory ErrorHint.stepBlocked() = ErrorHintStepBlocked;

  /// *Probe a range*: the text is not an IPv4 range.
  const factory ErrorHint.rangeBadText() = ErrorHintRangeBadText;

  /// *Probe a range*: a part of the address is above 255.
  const factory ErrorHint.rangeBadPart() = ErrorHintRangeBadPart;

  /// *Probe a range*: the prefix is above 32.
  const factory ErrorHint.rangeBadPrefix() = ErrorHintRangeBadPrefix;

  /// *Probe a range*: more addresses than one probe takes.
  const factory ErrorHint.rangeTooBig() = ErrorHintRangeTooBig;

  /// *Probe a range*: the port is not 1 to 65535.
  const factory ErrorHint.portOutOfRange() = ErrorHintPortOutOfRange;

  /// A gateway did not answer the probe before a log-in: [why].
  const factory ErrorHint.noAnswer(AnswerFault why) = ErrorHintNoAnswer;

  /// Studio's own settings did not open or did not read at its start.
  const factory ErrorHint.settingsUnreadable() = ErrorHintSettingsUnreadable;

  /// This computer's platform ([host]) holds no device key.
  const factory ErrorHint.noDeviceKey(HostPlatform host) = ErrorHintNoDeviceKey;

  /// A file sent in parts ended at [offset] of [size] bytes.
  const factory ErrorHint.fileEndedEarly({
    required int offset,
    required int size,
  }) = ErrorHintFileEndedEarly;

  /// The system's prompt for the device key was cancelled.
  const factory ErrorHint.signCancelled() = ErrorHintSignCancelled;

  /// The system locked the device key out (too many tries).
  const factory ErrorHint.signLockedOut() = ErrorHintSignLockedOut;

  /// The device key no longer opens (the enrolled biometrics changed).
  const factory ErrorHint.signKeyGone() = ErrorHintSignKeyGone;

  /// This computer has no biometrics to open the device key with.
  const factory ErrorHint.signUnavailable() = ErrorHintSignUnavailable;

  /// An update from a file of the package [name], which no link runs.
  const factory ErrorHint.packageHasNoLink(String name) =
      ErrorHintPackageHasNoLink;

  /// The broker sent an empty part before the end of a file.
  const factory ErrorHint.emptyPart() = ErrorHintEmptyPart;
}
