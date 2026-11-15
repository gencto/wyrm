import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'system_notice.freezed.dart';

/// What System says in a toast when something went well (or a file could
/// not be saved): typed, so `ui` words it in the language on screen
/// (studio-rules §5).
@freezed
sealed class SystemNotice with _$SystemNotice {
  /// `sys/profiles ▸ put` took the profile [name].
  const factory SystemNotice.profilePut(String name) = ProfilePutNotice;

  /// `sys/profiles ▸ remove` removed the profile [name].
  const factory SystemNotice.profileRemoved(String name) = ProfileRemovedNotice;

  /// A command of Maintenance is on the clipboard.
  const factory SystemNotice.commandCopied() = CommandCopiedNotice;

  /// The address [url] of the operations guide is on the clipboard.
  const factory SystemNotice.guideCopied(String url) = GuideCopiedNotice;

  /// [lines] log lines are on the clipboard.
  const factory SystemNotice.logCopied(int lines) = LogCopiedNotice;

  /// The log lines were saved to [path].
  const factory SystemNotice.logSaved(String path) = LogSavedNotice;

  /// The log lines could not be saved: [error].
  const factory SystemNotice.logNotSaved(String error) = LogNotSavedNotice;

  /// `clear_conns` removed the links [ids] (none: nothing to remove).
  const factory SystemNotice.cleared(IList<String> ids) = ClearedNotice;
}
