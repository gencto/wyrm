import '../../app_state.dart';
import '../../common/action.dart';
import '../models/broker_update_state.dart';

/// Closes the broker update dialog. An update that runs goes on.
class CloseBrokerUpdateAction extends Action {
  @override
  AppState reduce() => state.copyWith(brokerUpdate: const BrokerUpdateState());
}
