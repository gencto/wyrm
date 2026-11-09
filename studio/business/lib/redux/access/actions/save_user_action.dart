import 'dart:async';

import 'package:async_redux/async_redux.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../app_state.dart';
import '../../common/action.dart';
import 'retrieve_access_action.dart';

/// Adds a user ([password] required) or changes one: roles, a new password,
/// disabled. The gateway's own message is shown when it refuses.
class SaveUserAction extends Action with WaitingAction {
  SaveUserAction(
    this.name, {
    this.roles,
    this.password,
    this.disabled,
    this.isNew = false,
  });

  final String name;
  final List<String>? roles;
  final String? password;
  final bool? disabled;
  final bool isNew;

  @override
  Future<AppState?> reduce() async {
    final s = deps.session;
    if (s == null) {
      return null;
    }
    try {
      if (isNew) {
        await s.addUser(name, password ?? '', roles ?? const []);
      } else {
        if (roles case final r?) {
          await s.setUserRoles(name, r);
        }
        if (password case final p? when p.isNotEmpty) {
          await s.setUserPassword(name, p);
        }
        if (disabled case final d?) {
          await s.setUserDisabled(name, disabled: d);
        }
      }
    } on WyrmException catch (e) {
      throw UserException('The gateway refused it.', reason: e.message);
    }
    return null;
  }

  @override
  void after() {
    super.after();
    unawaited(dispatchAndWait(RetrieveAccessAction()));
  }
}
