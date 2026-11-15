import 'package:models/studio_notice.dart';
import 'package:models/system_notice.dart';

import '../../../wyrm/failures.dart';
import '../../app_state.dart';
import '../../common/action.dart';

/// Something went well and is worth one line: a toast in `good`
/// ("Copied", "Removed 3 links"), gone by itself.
class ShowNoticeAction extends Action {
  ShowNoticeAction(this.title, {this.detail}) : notice = null;

  /// A notice of System, worded by `ui` in the language on screen.
  ShowNoticeAction.system(SystemNotice this.notice) : title = '', detail = null;

  final String title;
  final String? detail;
  final SystemNotice? notice;

  @override
  AppState reduce() => state.copyWith.problems(
    notices: state.problems.notices.add(
      StudioNotice(
        id: nextErrorId(),
        title: title,
        detail: detail,
        system: notice,
      ),
    ),
  );
}
