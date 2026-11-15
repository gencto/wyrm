import 'package:models/notice_kind.dart';
import 'package:models/studio_notice.dart';
import 'package:ui/alerts/toast_stack.dart';

// A notice as the toast stack draws it (studio-rules §3, §5): one
// exhaustive switch for what `ui` words.

extension NoticeKindCopied on NoticeKind {
  Copied get copied => switch (this) {
    NoticeKind.keyCopied => .key,
    NoticeKind.keysCopied => .keys,
    NoticeKind.valueCopied => .value,
  };
}

extension StudioNoticeToast on StudioNotice {
  /// A success toast, in `good` for 3 s: `ui` words a [kind], else the
  /// notice's own [title].
  ToastVm get toast => switch (kind) {
    final k? => ToastVm.copied(id, k.copied, count: count),
    null => ToastVm(
      id: id,
      tone: .good,
      title: title,
      line: detail ?? '',
      seconds: 3,
    ),
  };
}
