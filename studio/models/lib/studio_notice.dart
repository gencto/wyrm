import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'notice_kind.dart';
import 'system_notice.dart';
import 'withheld_args.dart';

part 'studio_notice.freezed.dart';

/// Something that went well, said in a toast of the same shape as a quiet
/// error, in `good` (docs/design/specs/errors.md §4): "Copied", "Saved".
@freezed
abstract class StudioNotice with _$StudioNotice {
  const factory StudioNotice({
    /// From the same counter as `StudioError.id`, so the toasts keep the
    /// order they came in.
    required int id,

    /// What it says, when it is not a [system] notice; `ui` words it.
    NoticeKind? kind,

    /// How many keys were copied ([NoticeKind.keysCopied]).
    @Default(0) int count,

    /// Where a file went ([NoticeKind.planSaved]).
    String? path,

    /// The arguments a saved plan left out ([NoticeKind.planSaved]).
    @Default(IListConst([])) IList<WithheldArgs> leftOut,

    /// A notice of System, worded by `ui`.
    SystemNotice? system,
  }) = _StudioNotice;
}
