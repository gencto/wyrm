import 'package:freezed_annotation/freezed_annotation.dart';

part 'view_check.freezed.dart';

/// One line of the Checks tab of a view (docs/design/specs/genui-views.md
/// §4): what was checked and how it came out.
@freezed
abstract class ViewCheck with _$ViewCheck {
  const factory ViewCheck({
    /// `ok`, `warn` (drawn, with a placeholder or without an effect) or
    /// `bad` (the document is refused or a part cannot work).
    required String level,

    /// The sentence shown.
    required String text,

    /// The component the line is about, if one.
    String? part,

    /// The key the line is about, if one.
    String? key,
  }) = _ViewCheck;
}
