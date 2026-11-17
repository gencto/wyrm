import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/notice_kind.dart';
import 'package:models/studio_notice.dart';
import 'package:models/system_notice.dart';
import 'package:models/withheld_args.dart';

import '../../../wyrm/failures.dart';
import '../../app_state.dart';
import '../../common/action.dart';

/// Something went well and is worth one line: a toast in `good`
/// ("Copied", "Removed 3 links"), gone by itself. It is named, never
/// worded: `ui` says it in the language on screen (studio-rules §5).
class ShowNoticeAction extends Action {
  /// A notice of [kind]; a saved plan with its [path] and the arguments
  /// it [leftOut].
  ShowNoticeAction(
    NoticeKind this.kind, {
    this.path,
    this.leftOut = const IListConst([]),
  }) : notice = null;

  /// A notice of System.
  ShowNoticeAction.system(SystemNotice this.notice)
    : kind = null,
      path = null,
      leftOut = const IListConst([]);

  final NoticeKind? kind;
  final String? path;
  final IList<WithheldArgs> leftOut;
  final SystemNotice? notice;

  @override
  AppState reduce() => state.copyWith.problems(
    notices: state.problems.notices.add(
      StudioNotice(
        id: nextErrorId(),
        kind: kind,
        path: path,
        leftOut: leftOut,
        system: notice,
      ),
    ),
  );
}
