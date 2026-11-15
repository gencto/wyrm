import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:wyrm_core/wyrm_core.dart';

part 'library_off.freezed.dart';

/// Why the site's library of custom blocks is off in the flow editor
/// (`dataflows` ▸ `list_blocks`, ADR 0040 §3); none while it answers.
@freezed
sealed class LibraryOff with _$LibraryOff {
  /// Not read yet: custom blocks are off until it answers.
  const factory LibraryOff.unread() = LibraryOffUnread;

  /// The broker did not answer it: an older broker, or no right.
  const factory LibraryOff.refused(StatusCode status) = LibraryOffRefused;
}
