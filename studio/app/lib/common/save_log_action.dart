import 'dart:convert';

import 'package:business/redux/app_state.dart';
import 'package:business/redux/common/action.dart';
import 'package:business/redux/problems/actions/show_notice_action.dart';
import 'package:business/wyrm/mappers/log_line_mapper.dart';
import 'package:file_picker/file_picker.dart';
import 'package:models/system_notice.dart';

/// `Save as .log` of System's Log tab: the lines the log box shows, one
/// record per line, to a file the user picks (`wyrm-<site>-<time>.log`);
/// a toast says where, or why it could not be saved. Nothing when the box
/// shows no line, or the user leaves the picker.
///
/// In `app`: the file picker is a plugin of the app, not of `business`.
class SaveLogAction extends Action {
  @override
  Future<AppState?> reduce() async {
    final lines = shownLog;
    if (lines.isEmpty) {
      return null;
    }
    final Uri? saved;
    try {
      // The picker writes the bytes itself (file_picker 12+).
      saved = await FilePicker.saveFile(
        fileName: logFileName(site.viewed ?? 'site', DateTime.now()),
        bytes: utf8.encode('${logText(lines)}\n'),
        mimeType: 'text/plain',
      );
    } on Object catch (e) {
      await dispatchAndWait(
        ShowNoticeAction.system(SystemNotice.logNotSaved('$e')),
      );
      return null;
    }
    if (saved == null) {
      return null;
    }
    final notice = SystemNotice.logSaved(
      saved.isScheme('file') ? saved.toFilePath() : '$saved',
    );
    await dispatchAndWait(ShowNoticeAction.system(notice));
    return null;
  }
}
