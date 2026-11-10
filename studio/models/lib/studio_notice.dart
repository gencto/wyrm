import 'package:freezed_annotation/freezed_annotation.dart';

part 'studio_notice.freezed.dart';

/// Something that went well, said in a toast of the same shape as a quiet
/// error, in `good` (docs/design/specs/errors.md §4): "Copied", "Saved".
@freezed
abstract class StudioNotice with _$StudioNotice {
  const factory StudioNotice({
    /// From the same counter as `StudioError.id`, so the toasts keep the
    /// order they came in.
    required int id,
    required String title,

    /// One line under the title.
    String? detail,
  }) = _StudioNotice;
}
