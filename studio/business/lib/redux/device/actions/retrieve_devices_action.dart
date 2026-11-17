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
      final devices = newestFirst(await session.devices());
      // The rows are shown as of this read (`clock.now`): used just now,
      // days left before the password is due.
      return state.copyWith(
        device: state.device.copyWith(devices: devices),
        clock: state.clock.copyWith(now: deps.clock()),
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
