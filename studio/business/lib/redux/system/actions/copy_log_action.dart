import 'package:models/system_notice.dart';

import '../../../wyrm/mappers/log_line_mapper.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import 'copy_text_action.dart';

/// `Copy` of the Log tab: the lines the log box shows, one record per
/// line, on the clipboard. Nothing when it shows none.
class CopyLogAction extends Action {
  @override
  Future<AppState?> reduce() async {
    final lines = shownLog;
    if (lines.isEmpty) {
      return null;
    }
    await dispatchAndWait(
      CopyTextAction(logText(lines), SystemNotice.logCopied(lines.length)),
    );
    return null;
  }
}
