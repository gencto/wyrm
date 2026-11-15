import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:flutter/foundation.dart';

/// Runs [inner] to its end, then tells [closed] when it went well (the
/// dialog that started it closes): one intent, one dispatch
/// (studio-rules §1, §9), the dialog's own close beside it. It changes no
/// state itself (`null`).
class CloseOnOkAction extends ReduxAction<AppState> {
  CloseOnOkAction(this.inner, {required this.closed});

  final ReduxAction<AppState> inner;
  final VoidCallback closed;

  @override
  Future<AppState?> reduce() async {
    if ((await dispatchAndWait(inner)).isCompletedOk) {
      closed();
    }
    return null;
  }
}
