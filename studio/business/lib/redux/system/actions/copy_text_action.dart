import 'package:flutter/services.dart';
import 'package:models/system_notice.dart';

import '../../app_state.dart';
import '../../common/action.dart';
import '../../problems/actions/show_notice_action.dart';

/// Puts [text] on the clipboard, then says so with [notice].
class CopyTextAction extends Action {
  CopyTextAction(this.text, this.notice);

  final String text;
  final SystemNotice notice;

  @override
  Future<AppState?> reduce() async {
    await Clipboard.setData(ClipboardData(text: text));
    await dispatchAndWait(ShowNoticeAction.system(notice));
    return null;
  }
}
