import 'package:freezed_annotation/freezed_annotation.dart';

import 'notice_kind.dart';

part 'studio_notice.freezed.dart';

/// Something that went well, said in a toast of the same shape as a quiet
/// error, in `good` (docs/design/specs/errors.md §4): "Copied", "Saved".
@freezed
abstract class StudioNotice with _$StudioNotice {
  const factory StudioNotice({
    /// From the same counter as `StudioError.id`, so the toasts keep the
    /// order they came in.
    required int id,

    /// The words, when the one who said it has them; empty for a [kind]
    /// whose words `ui` says.
    @Default('') String title,

    /// What the notice says, when `ui` words it (with [count]).
    NoticeKind? kind,
    @Default(0) int count,

    /// One line under the title.
    String? detail,
  }) = _StudioNotice;
}
