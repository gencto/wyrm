import 'package:models/studio_notice.dart';

import '../../../wyrm/failures.dart';
import '../../app_state.dart';
import '../../common/action.dart';

/// Something went well and is worth one line: a toast in `good`
/// ("Copied", "Removed 3 links"), gone by itself.
class ShowNoticeAction extends Action {
  ShowNoticeAction(this.title, {this.detail});

  final String title;
  final String? detail;

  @override
  AppState reduce() => state.copyWith.problems(
    notices: state.problems.notices.add(
      StudioNotice(id: nextErrorId(), title: title, detail: detail),
    ),
  );
}
