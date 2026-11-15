import 'package:equatable/equatable.dart';
import 'package:localization/localization.dart';

/// What System says in a toast, worded in the language on screen.
enum SysToast {
  profilePut,
  profileRemoved,
  commandCopied,
  guideCopied,
  logCopied,
  logSaved,
  logNotSaved,
  cleared,
  clearedNone,
}

/// A toast of System: what it says, about what (a profile, an address, a
/// path, an error), the ids cleared and how many (log lines).
final class SysToastVm extends Equatable {
  const SysToastVm(
    this.kind, {
    this.subject = '',
    this.items = const [],
    this.count = 0,
  });

  final SysToast kind;
  final String subject;
  final List<String> items;
  final int count;

  String get title => switch (kind) {
    SysToast.profilePut => S.current.sysProfilePut(subject),
    SysToast.profileRemoved => S.current.sysProfileRemoved(subject),
    SysToast.commandCopied => S.current.sysCommandCopied,
    SysToast.guideCopied => S.current.sysGuideCopied(subject),
    SysToast.logCopied => S.current.sysLogCopied(count),
    SysToast.logSaved => S.current.sysLogSaved(subject),
    SysToast.logNotSaved => S.current.sysLogNotSaved,
    SysToast.cleared => S.current.sysCleared(items.join(', ')),
    SysToast.clearedNone => S.current.sysClearedNone,
  };

  /// The line under the title: the error of a log not saved.
  String get line => switch (kind) {
    SysToast.logNotSaved => subject,
    SysToast.profilePut ||
    SysToast.profileRemoved ||
    SysToast.commandCopied ||
    SysToast.guideCopied ||
    SysToast.logCopied ||
    SysToast.logSaved ||
    SysToast.cleared ||
    SysToast.clearedNone => '',
  };

  @override
  List<Object?> get props => [kind, subject, items, count];
}
