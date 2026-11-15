import 'package:models/studio_notice.dart';
import 'package:ui/alerts/toast_stack.dart';

import 'system_mappers.dart';

extension StudioNoticeToast on StudioNotice {
  /// The toast of a notice, in `good`, gone after 3 s: a notice of System
  /// typed (`ui` words it), else its own title and line.
  ToastVm get toast => switch (system?.toast) {
    final w? => ToastVm.system(id: id, words: w),
    null => ToastVm(
      id: id,
      tone: .good,
      title: title,
      line: detail ?? '',
      seconds: 3,
    ),
  };
}
