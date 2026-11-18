import 'package:equatable/equatable.dart';
import 'package:localization/localization.dart';

import '../indicators/device_os.dart';
import '../pages/install_checks.dart' show ManifestProblemVm;
import '../pages/log_in_data.dart' show AnswerWhy;

/// A refusal Studio words itself that has no parameter: where the broker
/// sent no words, or what Studio found wrong before or after a call.
enum HintTag {
  runDenied,
  runNotRunning,
  runNoTrigger,
  runNotByHand,
  notSettable,
  notConnected,
  noAssistant,
  assistantNoTask,
  agentParamsUnread,
  noEditAction,
  backupNoDigest,
  backupDigestMismatch,
  checkNotRun,
  stepBlocked,
  rangeBadText,
  rangeBadPart,
  rangeBadPrefix,
  rangeTooBig,
  portOutOfRange,
  emptyPart,
  signCancelled,
  signLockedOut,
  signKeyGone,
  signUnavailable,
  settingsUnreadable;

  String get text {
    final s = S.current;
    return switch (this) {
      runDenied => s.errRunDenied,
      runNotRunning => s.errRunNotRunning,
      runNoTrigger => s.errRunNoTrigger,
      runNotByHand => s.errRunNotByHand,
      notSettable => s.errNotSettable,
      notConnected => s.errNotConnected,
      noAssistant => s.errNoAssistant,
      assistantNoTask => s.errAssistantNoTask,
      agentParamsUnread => s.errAgentParamsUnread,
      noEditAction => s.errNoEditAction,
      backupNoDigest => s.errBackupNoDigest,
      backupDigestMismatch => s.errBackupDigestMismatch,
      checkNotRun => s.errCheckNotRun,
      stepBlocked => s.errStepBlocked,
      rangeBadText => s.rangeBadText,
      rangeBadPart => s.rangeBadPart,
      rangeBadPrefix => s.rangeBadPrefix,
      rangeTooBig => s.rangeTooBig,
      portOutOfRange => s.errPortOutOfRange,
      emptyPart => s.errEmptyPart,
      signCancelled => s.errSignCancelled,
      signLockedOut => s.errSignLockedOut,
      signKeyGone => s.errSignKeyGone,
      signUnavailable => s.errSignUnavailable,
      settingsUnreadable => s.fatalBody,
    };
  }
}

/// What Studio says of a failure the broker sent no words for, or of what
/// Studio itself found wrong: one sentence per case, in the language on
/// screen. A name, a field or a reason in it is data, as it came.
sealed class ErrorHintVm extends Equatable {
  const ErrorHintVm();

  /// A sentence without a parameter.
  const factory ErrorHintVm.tag(HintTag tag) = HintTagVm;

  /// An answer that is not one Studio reads: [field] of it (its wire
  /// name; empty when only the log names it).
  const factory ErrorHintVm.unreadable(
    UnreadableThing what, {
    String name,
    String field,
  }) = HintUnreadableVm;

  /// A file the user picked that is not of the form its kind has: what is
  /// wrong with it.
  const factory ErrorHintVm.fileNotRead(ManifestProblemVm problem) =
      HintFileNotReadVm;

  /// A gateway did not answer: why.
  const factory ErrorHintVm.noAnswer(AnswerWhy why) = HintNoAnswerVm;

  /// This computer holds no device key.
  const factory ErrorHintVm.noDeviceKey(DeviceOs os) = HintNoDeviceKeyVm;

  /// A file sent in parts ended at [offset] of [size] bytes.
  const factory ErrorHintVm.fileEndedEarly(int offset, int size) =
      HintFileEndedEarlyVm;

  /// A package that no link runs.
  const factory ErrorHintVm.packageHasNoLink(String name) =
      HintPackageHasNoLinkVm;

  /// The sentence.
  String get text;
}

final class HintTagVm extends ErrorHintVm {
  const HintTagVm(this.tag);

  final HintTag tag;

  @override
  String get text => tag.text;

  @override
  List<Object?> get props => [tag];
}

/// What an answer that does not read is: an answer of a call, some
/// entries of a list, a task's record, a library block, a flow's
/// definition.
enum UnreadableThing { answer, rows, taskRecord, libraryBlock, flowDef }

final class HintUnreadableVm extends ErrorHintVm {
  const HintUnreadableVm(this.what, {this.name = '', this.field = ''});

  final UnreadableThing what;

  /// The task, the block or the flow.
  final String name;

  /// The field that does not read, by its wire name; empty for the whole.
  final String field;

  @override
  String get text {
    final s = S.current;
    final whole = switch (what) {
      UnreadableThing.answer => s.errUnreadableAnswer,
      UnreadableThing.rows => s.errUnreadableRows,
      UnreadableThing.taskRecord => s.errTaskRecordInvalid(name),
      UnreadableThing.libraryBlock => s.errLibraryBlockInvalid(name),
      UnreadableThing.flowDef => s.errFlowDefInvalid(name),
    };
    return field.isEmpty ? whole : s.errUnreadableField(whole, field);
  }

  @override
  List<Object?> get props => [what, name, field];
}

final class HintFileNotReadVm extends ErrorHintVm {
  const HintFileNotReadVm(this.problem);

  final ManifestProblemVm problem;

  @override
  String get text {
    final p = problem;
    // a file without a name is `this`
    final named = p.file.isNotEmpty
        ? p
        : ManifestProblemVm(
            kind: p.kind,
            file: S.current.errThingThis,
            field: p.field,
            found: p.found,
            offset: p.offset,
          );
    return S.current.errFileNotReadBecause(named.line);
  }

  @override
  List<Object?> get props => [problem];
}

final class HintNoAnswerVm extends ErrorHintVm {
  const HintNoAnswerVm(this.why);

  final AnswerWhy why;

  @override
  String get text => why.words;

  @override
  List<Object?> get props => [why];
}

final class HintNoDeviceKeyVm extends ErrorHintVm {
  const HintNoDeviceKeyVm(this.os);

  final DeviceOs os;

  @override
  String get text => S.current.errNoDeviceKey(os.system);

  @override
  List<Object?> get props => [os];
}

final class HintFileEndedEarlyVm extends ErrorHintVm {
  const HintFileEndedEarlyVm(this.offset, this.size);

  final int offset;
  final int size;

  @override
  String get text => S.current.errFileEndedEarly(offset, size);

  @override
  List<Object?> get props => [offset, size];
}

final class HintPackageHasNoLinkVm extends ErrorHintVm {
  const HintPackageHasNoLinkVm(this.name);

  final String name;

  @override
  String get text => S.current.errPackageHasNoLink(name);

  @override
  List<Object?> get props => [name];
}
