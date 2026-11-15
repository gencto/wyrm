import 'package:flutter/services.dart';
import 'package:models/notice_kind.dart';
import 'package:models/studio_notice.dart';

import '../../../wyrm/failures.dart';
import '../../app_state.dart';
import '../../common/action.dart';

/// Copies [keys], one per line, and says so in a toast (`Key copied`,
/// `3 keys copied`). Nothing for none.
class CopyKeysAction extends Action {
  CopyKeysAction(this.keys);

  final List<String> keys;

  @override
  Future<AppState?> reduce() async {
    if (keys.isEmpty) {
      return null;
    }
    await Clipboard.setData(ClipboardData(text: keys.join('\n')));
    return state.copyWith.problems(
      notices: state.problems.notices.add(
        StudioNotice(
          id: nextErrorId(),
          kind: keys.length == 1 ? NoticeKind.keyCopied : NoticeKind.keysCopied,
          count: keys.length,
        ),
      ),
    );
  }
}
