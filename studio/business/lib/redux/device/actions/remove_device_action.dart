import 'package:models/answer_fault.dart';
import 'package:models/error_hint.dart';
import 'package:models/error_kind.dart';
import 'package:models/unlock_stage.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../../wyrm/device_keys.dart';
import '../../../wyrm/failures.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import 'retrieve_devices_action.dart';
import 'retrieve_user_devices_action.dart';

/// `Turn off`, `Remove` and `Forget` (board `UnlockApp`, Access › Users):
/// `DELETE /api/devices/<id>`. The owner's delete forgets the record; an
/// administrator's of another user's device leaves a tombstone that names
/// them (ADR 0050 decision 7). This computer's own device also loses its
/// key and its record here, so the log-in page asks for the password.
/// [user] is the drawer's user, whose list is read again; null is the
/// signed-in user's own list.
class RemoveDeviceAction extends Action with WaitingAction {
  RemoveDeviceAction(this.id, {this.user});

  final String id;
  final String? user;

  @override
  Future<AppState?> reduce() async {
    final session = deps.session;
    if (session == null) {
      return null;
    }
    try {
      await session.removeDevice(id);
    } on WyrmException catch (e) {
      // Gone already: what the list showed is out of date, nothing else.
      if (e.status != StatusCode.of(Status.notFound)) {
        throw StudioException.refused(
          e,
          call: const .known(.remove),
          thing: id,
          subject: .device,
        );
      }
    } on Object catch (e) {
      throw StudioException.hinted(
        ErrorKind.reach,
        // what was thrown says the URL it was asked on: its type only
        ErrorHint.noAnswer(AnswerFault.failed('${e.runtimeType}')),
        call: const .known(.remove),
        thing: id,
        subject: .device,
      );
    }
    // The list read again first; what this returns is made of the state
    // after it.
    final own = id == state.device.deviceId;
    await dispatchAndWait(switch (user) {
      final u? => RetrieveUserDevicesAction(u, quiet: true),
      null => RetrieveDevicesAction(quiet: true),
    });
    return own ? await forgetOwnKey(this) : null;
  }
}

/// This computer's key of the form's user is deleted with its record; the
/// choices (lock delay, `Don't ask`) stay.
Future<AppState> forgetOwnKey(Action a) async {
  final account = accountOf(a.login.gateway, a.login.user);
  if (a.state.device.keyId case final alias?) {
    await a.deps.deviceKey.delete(alias);
  }
  if (account != null) {
    final records = a.deps.deviceRecords;
    final r = await records.read(account.origin, account.user);
    await records.write(
      account.origin,
      account.user,
      r.copyWith(
        deviceId: () => null,
        alias: () => null,
        stale: false,
        added: 0,
        lastUsed: 0,
      ),
    );
  }
  return a.state.copyWith.device(
    keyId: null,
    deviceId: null,
    added: 0,
    lastUsed: 0,
    stale: false,
    stage: UnlockStage.none,
  );
}
