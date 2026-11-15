import 'package:models/notice_kind.dart';
import 'package:models/studio_notice.dart';
import 'package:ui/alerts/toast_stack.dart';

import 'system_mappers.dart';

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
  /// The toast of a notice, in `good`, gone after 3 s: what was copied or a
  /// notice of System (`ui` words them), else its own title and line.
  ToastVm get toast => switch ((kind, system?.toast)) {
    (final k?, _) => ToastVm.copied(id, k.copied, count: count),
    (null, final w?) => ToastVm.system(id: id, words: w),
    (null, null) => ToastVm(
      id: id,
      tone: .good,
      title: title,
      line: detail ?? '',
      seconds: 3,
    ),
  };
}
