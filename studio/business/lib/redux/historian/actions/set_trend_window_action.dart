import 'dart:async';

import 'package:models/hist_window.dart';

import '../../app_state.dart';
import '../../common/action.dart';
import 'load_trend_window_action.dart';

/// The trend's window, from the brush, a drag on the plot, the wheel or
/// `Reset zoom` (null: the whole range). A window whose right edge is the
/// range's end follows now ([HistWindow.end] null). Reads it finer once it
/// stopped moving ([LoadTrendWindowAction]); every change supersedes a read
/// in flight (`trendGen`).
class SetTrendWindowAction extends Action {
  SetTrendWindowAction(this.next);

  final HistWindow? next;

  @override
  AppState? reduce() {
    if (next == historian.window) {
      return null;
    }
    return state.copyWith.historian(
      window: next,
      trendGen: historian.trendGen + 1,
      detail: next == null ? null : historian.detail,
    );
  }

  @override
  void after() {
    super.after();
    if (status.hasFinishedMethodReduce) {
      unawaited(dispatchAndWait(LoadTrendWindowAction()));
    }
  }
}
