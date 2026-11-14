import 'package:models/error_kind.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../../wyrm/device_keys.dart';
import '../../../wyrm/failures.dart';
import '../../app_state.dart';
import '../../common/action.dart';

/// The devices of [user] in the Access › Users drawer
/// (`GET /api/users/<u>/devices`, admin).
class RetrieveUserDevicesAction extends Action with WaitingAction {
  RetrieveUserDevicesAction(this.user, {super.quiet});

  final String user;

  @override
  Action again() => RetrieveUserDevicesAction(user);

  @override
  Future<AppState?> reduce() async {
    final session = deps.session;
    if (session == null) {
      return null;
    }
    try {
      final ds = await session.userDevices(user);
      return state.copyWith.device(
        userDevices: state.device.userDevices.add(user, userDevicesOf(ds)),
      );
    } on WyrmException catch (e) {
      throw StudioException.refused(e, call: 'devices', thing: user);
    } on Object catch (e) {
      throw StudioException.said(
        ErrorKind.reach,
        faultLine(e),
        call: 'devices',
        thing: user,
      );
    }
  }
}
