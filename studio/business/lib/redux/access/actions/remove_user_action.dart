import 'package:wyrm_client/wyrm_client.dart';

import '../../../wyrm/failures.dart';
import '../../app_state.dart';
import '../../common/action.dart';

/// Removes a user of the gateway.
class RemoveUserAction extends Action with WaitingAction {
  RemoveUserAction(this.name);

  final String name;

  @override
  Future<AppState?> reduce() async {
    try {
      await deps.session?.removeUser(name);
    } on WyrmException catch (e) {
      throw StudioException.refused(
        e,
        call: 'remove_user',
        thing: name,
        write: true,
      );
    }
    return state.copyWith.access(
      users: access.users.removeWhere((u) => u.name == name),
      selected: null,
    );
  }
}
