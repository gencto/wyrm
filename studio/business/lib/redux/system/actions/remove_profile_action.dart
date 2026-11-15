import 'package:async_redux/async_redux.dart';
import 'package:models/system_notice.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../../wyrm/calls.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import '../../problems/actions/show_notice_action.dart';
import 'retrieve_profiles_action.dart';

/// `sys/profiles` ▸ `remove {name}` (config); audited by the broker
/// (`profile_remove`). The list is read again,
/// and a toast says so.
class RemoveProfileAction extends Action with NonReentrant, WaitingAction {
  RemoveProfileAction(this.name);

  @override
  Action again() => RemoveProfileAction(name);

  @override
  Action reload() => RetrieveProfilesAction();

  final String name;

  @override
  Future<AppState?> reduce() async {
    await invokeAll(
      deps.wyrm,
      '${site.root}/sys/profiles',
      'remove',
      Value.from({'name': name}),
    );
    await dispatchAndWait(RetrieveProfilesAction());
    await dispatchAndWait(
      ShowNoticeAction.system(SystemNotice.profileRemoved(name)),
    );
    return null;
  }
}
