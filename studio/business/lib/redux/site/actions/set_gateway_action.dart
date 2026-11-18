import '../../../wyrm/session.dart';
import '../../app_state.dart';
import '../../common/action.dart';

class SetGatewayAction extends Action {
  SetGatewayAction(this.gateway);

  final GatewayAddress? gateway;

  @override
  AppState reduce() => state.copyWith.site(gateway: gateway);
}
