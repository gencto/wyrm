import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/answer_fault.dart';
import 'package:models/audit_line.dart';
import 'package:models/error_hint.dart';
import 'package:models/error_kind.dart';
import 'package:models/role_grant.dart';
import 'package:models/user_info.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../../wyrm/decode/access.dart';
import '../../../wyrm/failures.dart';
import '../../app_state.dart';
import '../../common/action.dart';

/// Reads Access: the gateway's users (`/api/users`), every grant
/// (`sys` ▸ `get_permissions`) and the audit tail (`sys/audit` ▸ `tail`).
/// What the user may not read stays empty.
class RetrieveAccessAction extends Action with WaitingAction {
  @override
  Action again() => RetrieveAccessAction();

  @override
  Future<AppState?> reduce() => readAccess(this);
}

/// One read of Access: users, grants and the audit tail. Shared by the
/// read when the tab is shown and the repeat every 10 s
/// (`PollAccessAction`). Selection and tab are not touched, so the open
/// inspector stays.
Future<AppState?> readAccess(Action a) async {
  final root = a.site.home;
  final session = a.deps.session;
  if (root == null || session == null) {
    return null;
  }
  var users = const <UserInfo>[];
  try {
    users = [
      for (final u in await session.users())
        UserInfo(
          name: u.name,
          roles: u.roles.lock,
          disabled: u.disabled,
          devices: u.devices,
        ),
    ];
  } on WyrmException {
    // Not an administrator of the gateway.
  } on Object catch (e) {
    throw StudioException.hinted(
      ErrorKind.reach,
      // what was thrown says the URL it was asked on: its type only
      ErrorHint.noAnswer(AnswerFault.failed('${e.runtimeType}')),
      call: const .known(.users),
    );
  }
  final grants = <RoleGrant>[];
  try {
    final rows = await a.deps.wyrm
        .invoke('$root/sys', 'get_permissions')
        .toList();
    for (final r in recordsOf(rows)) {
      if (roleGrantOf(r).orWarn('get_permissions') case final g?) {
        grants.add(g);
      }
    }
  } on WyrmException {
    // No config on sys.
  }
  final audit = <AuditLine>[];
  try {
    final rows = await a.deps.wyrm
        .invoke('$root/sys/audit', 'tail', Value.from({'n': 200}))
        .toList();
    for (final r in recordsOf(rows)) {
      if (auditLineOf(r).orWarn('audit tail') case final l?) {
        audit.add(l);
      }
    }
  } on WyrmException {
    // No config on sys.
  }
  return a.state.copyWith.access(
    users: users.lock,
    grants: grants.lock,
    audit: audit.reversed.toList().lock,
  );
}
