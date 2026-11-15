import 'package:flutter/services.dart';
import 'package:models/notice_kind.dart';
import 'package:models/studio_notice.dart';

import '../../../wyrm/failures.dart';
import '../../app_state.dart';
import '../../common/action.dart';

/// ⌘C in Explorer: copies the value of the point in the inspector, as the
/// user reads it, and says so in a toast.
class CopyValueAction extends Action {
  CopyValueAction(this.value);

  final String value;

  @override
  Future<AppState?> reduce() async {
    await Clipboard.setData(ClipboardData(text: value));
    return state.copyWith.problems(
      notices: state.problems.notices.add(
        StudioNotice(id: nextErrorId(), kind: NoticeKind.valueCopied),
      ),
    );
  }
}
