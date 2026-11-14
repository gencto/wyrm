import 'dart:async';

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
        throw StudioException.refused(e, call: 'remove', thing: 'device $id');
      }
    } on Object catch (e) {
      throw StudioException.said(
        ErrorKind.reach,
        faultLine(e),
        call: 'remove',
        thing: 'device $id',
      );
    }
    var next = state;
    if (id == state.device.deviceId) {
      next = await forgetOwnKey(this);
    }
    if (user case final u?) {
      unawaited(dispatchAndWait(RetrieveUserDevicesAction(u, quiet: true)));
    } else {
      unawaited(dispatchAndWait(RetrieveDevicesAction(quiet: true)));
    }
    return next;
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
