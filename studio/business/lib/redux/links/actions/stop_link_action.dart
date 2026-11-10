import 'package:async_redux/async_redux.dart';

import '../../../wyrm/calls.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import 'retrieve_links_action.dart';

/// `sys/links/<id>` ▸ `stop` (config): it stays installed; its points go bad
/// until it is started again.
class StopLinkAction extends Action with NonReentrant, WaitingAction {
  StopLinkAction(this.id);

  @override
  Action again() => StopLinkAction(id);

  @override
  Action reload() => RetrieveLinksAction();

  final String id;

  @override
  Future<AppState?> reduce() async {
    await invokeAll(deps.wyrm, '${site.root}/sys/links/$id', 'stop');
    return null;
  }
}
