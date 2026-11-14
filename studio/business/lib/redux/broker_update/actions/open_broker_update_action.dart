import '../../app_state.dart';
import '../../common/action.dart';
import '../models/broker_update_state.dart';

/// Opens the broker update dialog (boards `BrokerUpdate*`, ADR 0048 §2):
/// its review, or with [follow] what the broker says of the update that
/// runs or ended (`sys/update_state`, `sys/update_last`).
class OpenBrokerUpdateAction extends Action {
  OpenBrokerUpdateAction({this.follow = false});

  final bool follow;

  @override
  AppState reduce() => state.copyWith(
    brokerUpdate: BrokerUpdateState(stage: follow ? 'follow' : 'review'),
  );
}
