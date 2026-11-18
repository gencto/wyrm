import 'package:async_redux/async_redux.dart';
import 'package:models/answer_fault.dart';
import 'package:models/error_hint.dart';
import 'package:models/error_kind.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../../wyrm/failures.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import '../../session/actions/log_out_action.dart';
import 'remove_device_action.dart';

/// `Sign out everywhere` (`POST /api/me/sign-out`): every session of the
/// user ends and every device is signed out, this one too (a new user
/// generation, ADR 0050 decision 5). This computer's device is turned off
/// first, so its key goes with it, then Studio logs out.
class SignOutEverywhereAction extends Action with NonReentrant, WaitingAction {
  @override
  Future<AppState?> reduce() async {
    final session = deps.session;
    if (session == null) {
      return null;
    }
    if (state.device.deviceId case final id?) {
      try {
        await session.removeDevice(id);
      } on Object {
        // The sign-out below ends it anyway.
      }
    }
    try {
      await session.signOutEverywhere();
    } on WyrmException catch (e) {
      throw StudioException.refused(e, call: const .known(.signOut));
    } on Object catch (e) {
      throw StudioException.hinted(
        ErrorKind.reach,
        // what was thrown says the URL it was asked on: its type only
        ErrorHint.noAnswer(AnswerFault.failed('${e.runtimeType}')),
        call: const .known(.signOut),
      );
    }
    final forgotten = await forgetOwnKey(this);
    await deps.detach();
    return loggedOut(forgotten);
  }
}
