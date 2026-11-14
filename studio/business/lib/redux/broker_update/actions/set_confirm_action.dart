import '../../app_state.dart';
import '../../common/action.dart';

class SetConfirmAction extends Action {
  SetConfirmAction(this.confirm);

  final String confirm;

  @override
  AppState reduce() => state.copyWith.brokerUpdate(confirm: confirm);
}
