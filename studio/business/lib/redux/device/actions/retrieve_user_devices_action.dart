import 'package:models/answer_fault.dart';
import 'package:models/error_hint.dart';
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
      // The rows are shown as of this read (`clock.now`).
      return state.copyWith(
        device: state.device.copyWith(
          userDevices: state.device.userDevices.add(user, newestFirst(ds)),
        ),
        clock: state.clock.copyWith(now: deps.clock()),
      );
    } on WyrmException catch (e) {
      throw StudioException.refused(
        e,
        call: const .known(.devices),
        thing: user,
      );
    } on Object catch (e) {
      throw StudioException.hinted(
        ErrorKind.reach,
        // what was thrown says the URL it was asked on: its type only
        ErrorHint.noAnswer(AnswerFault.failed('${e.runtimeType}')),
        call: const .known(.devices),
        thing: user,
      );
    }
  }
}
