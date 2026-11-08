import 'package:async_redux/async_redux.dart';

import '../../app_state.dart';
import '../../common/action.dart';

class AuthorizeBrokerAction extends Action with NonReentrant, WaitingAction {
  // One lock per action type: LoadX(a) is ignored while LoadX(b) is
  // running. Override to let each instance run on its own:
  // Object? nonReentrantKeyParams() => someId;

  // TODO(frx): async work guarded by the waiting barrier (see WaitingAction).
  @override
  Future<AppState?> reduce() async => null;
}
