import 'dart:async';

import 'package:wyrm_client/wyrm_client.dart';

import '../../../wyrm/calls.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import 'retrieve_access_action.dart';

/// `sys` ▸ `update_permissions {role, path, level}` (config): a role's
/// grant on a key pattern; `none` takes it back.
class SetGrantAction extends Action with WaitingAction {
  SetGrantAction(this.role, this.path, this.level);

  @override
  Action again() => SetGrantAction(role, path, level);

  @override
  Action reload() => RetrieveAccessAction();

  final String role;
  final String path;
  final String level;

  @override
  Future<AppState?> reduce() async {
    await invokeAll(
      deps.wyrm,
      '${site.home}/sys',
      'update_permissions',
      Value.from({'role': role, 'path': path, 'level': level}),
    );
    return null;
  }

  @override
  void after() {
    super.after();
    unawaited(dispatchAndWait(RetrieveAccessAction()));
  }
}
