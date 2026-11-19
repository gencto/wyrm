import 'package:business/wyrm/shell.dart';
import 'package:models/notice_kind.dart';
import 'package:models/studio_notice.dart';
import 'package:ui/alerts/toast_stack.dart';

import 'error_mappers.dart';
import 'system_mappers.dart';

// A notice as the toast stack draws it (studio-rules §3, §5): one
// exhaustive switch for what `ui` words.

extension StudioNoticeToast on StudioNotice {
  /// The toast of a notice, in `good`, gone after 3 s: `ui` words what
  /// was copied, a plan that was saved, or a notice of System.
  ToastVm get toast => switch ((system?.toast, kind)) {
    (final w?, _) => ToastVm.system(id: id, words: w),
    (null, NoticeKind.keyCopied) => ToastVm.copied(id, .key),
    (null, NoticeKind.keysCopied) => ToastVm.copied(id, .keys, count: count),
    (null, NoticeKind.valueCopied) => ToastVm.copied(id, .value),
    (null, NoticeKind.detailsCopied) => ToastVm.copied(id, .details),
    (null, NoticeKind.reportCopied) => ToastVm.copied(id, .report),
    (null, NoticeKind.draftCopied) => ToastVm.copied(id, .draft),
    (null, NoticeKind.planSaved) => ToastVm.planSaved(
      id,
      path: path ?? '',
      leftOut: [
        for (final l in leftOut)
          LeftOutVm(step: l.step, names: l.names.unlockView),
      ],
    ),
    // a notice that names nothing says nothing: never made by an action
    (null, null) => ToastVm(id: id, tone: .good, title: '', seconds: 3),
  };
}

extension ToastVmOf on Toast {
  /// A toast as the stack draws it: a quiet failure or a notice.
  ToastVm get vm => switch (this) {
    ErrorToast(:final error) => error.toast,
    NoticeToast(:final notice) => notice.toast,
  };
}
