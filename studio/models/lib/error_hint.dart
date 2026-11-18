import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'answer_fault.dart';
import 'host_platform.dart';

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

  /// The record of task [task] is not one Studio reads: its decoder says
  /// which [field] and what is wrong with it ([reason]).
  const factory ErrorHint.taskRecordInvalid({
    required String task,
    required String field,
    required String reason,
  }) = ErrorHintTaskRecordInvalid;

  /// The library block [name] is not one Studio reads.
  const factory ErrorHint.libraryBlockInvalid({
    required String name,
    required String field,
    required String reason,
  }) = ErrorHintLibraryBlockInvalid;

  /// The definition of flow [flow] is not one Studio reads: [why] is the
  /// decoder's `field: reason`.
  const factory ErrorHint.flowDefInvalid({
    required String flow,
    required String why,
  }) = ErrorHintFlowDefInvalid;

  /// The node has no `edit` action.
  const factory ErrorHint.noEditAction() = ErrorHintNoEditAction;

  /// A profile file that is not JSON; [detail] is the parser's own line.
  const factory ErrorHint.profileNotJson(String detail) =
      ErrorHintProfileNotJson;

  /// A profile file whose JSON is not an object.
  const factory ErrorHint.profileNotObject() = ErrorHintProfileNotObject;

  /// A profile with the key [key], which is none of [known].
  const factory ErrorHint.profileUnknownKey({
    required String key,
    required IList<String> known,
  }) = ErrorHintProfileUnknownKey;

  /// A profile entry of the type [type], which is not one.
  const factory ErrorHint.profileUnknownType(String type) =
      ErrorHintProfileUnknownType;

  /// A profile with too many entries to add `extends`.
  const factory ErrorHint.profileTooBig() = ErrorHintProfileTooBig;

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
