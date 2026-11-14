import '../../app_state.dart';
import '../../common/action.dart';

class SetTrustPendingAction extends Action {
  SetTrustPendingAction(this.trustPending);

  final String? trustPending;

  @override
  AppState reduce() => state.copyWith.discovery(trustPending: trustPending);
}
