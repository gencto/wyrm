import 'package:async_redux/async_redux.dart';

import '../../../wyrm/calls.dart';
import '../../app_state.dart';
import '../../common/action.dart';

/// `sys/links/<id>` ▸ `start` (config). The state follows as a live value.
class StartLinkAction extends Action with NonReentrant, WaitingAction {
  StartLinkAction(this.id);

  final String id;

  @override
  Future<AppState?> reduce() async {
    await invokeAll(deps.wyrm, '${site.root}/sys/links/$id', 'start');
    return null;
  }
}
