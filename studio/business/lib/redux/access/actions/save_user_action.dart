import 'package:wyrm_client/wyrm_client.dart';

import '../../../wyrm/failures.dart';
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
    // The table is read again, also after a refusal: it shows what is.
    // It changes no state itself: what it did shows in the table read.
    try {
      await _run();
    } finally {
      await dispatchAndWait(RetrieveAccessAction());
    }
    return null;
  }

  Future<void> _run() async {
    final s = deps.session;
    if (s == null) {
      return;
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
      throw StudioException.refused(
        e,
        call: const .known(.saveUser),
        thing: name,
        write: true,
      );
    }
    return;
  }
}
