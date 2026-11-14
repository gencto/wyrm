import 'package:models/error_kind.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../../wyrm/device_keys.dart';
import '../../../wyrm/failures.dart';
import '../../app_state.dart';
import '../../common/action.dart';

/// *Your devices on `<site>`* in Account › Security (`GET /api/devices`).
class RetrieveDevicesAction extends Action with WaitingAction {
  RetrieveDevicesAction({super.quiet});

  @override
  Action again() => RetrieveDevicesAction();

  @override
  Future<AppState?> reduce() async {
    final session = deps.session;
    if (session == null) {
      return null;
    }
    try {
      return state.copyWith.device(
        devices: userDevicesOf(await session.devices()),
      );
    } on WyrmException catch (e) {
      throw StudioException.refused(e, call: 'devices');
    } on Object catch (e) {
      throw StudioException.said(
        ErrorKind.reach,
        faultLine(e),
        call: 'devices',
      );
    }
  }
}
