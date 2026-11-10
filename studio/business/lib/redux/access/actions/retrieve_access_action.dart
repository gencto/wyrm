import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/error_kind.dart';
import 'package:models/role_grant.dart';
import 'package:models/user_info.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../../wyrm/failures.dart';
import '../../../wyrm/mappers/values.dart';
import '../../app_state.dart';
import '../../common/action.dart';

/// Reads Access: the gateway's users (`/api/users`), every grant
/// (`sys` ▸ `get_permissions`) and the audit tail (`sys/audit` ▸ `tail`).
/// What the user may not read stays empty.
class RetrieveAccessAction extends Action with WaitingAction {
  @override
  Action again() => RetrieveAccessAction();

  @override
  Future<AppState?> reduce() async {
    final root = site.home;
    final session = deps.session;
    if (root == null || session == null) {
      return null;
    }
    var users = const <UserInfo>[];
    try {
      users = [
        for (final u in await session.users())
          UserInfo(name: u.name, roles: u.roles.lock, disabled: u.disabled),
      ];
    } on WyrmException {
      // Not an administrator of the gateway.
    } on Object catch (e) {
      throw StudioException.said(
        ErrorKind.reach,
        faultLine(e),
        call: 'users',
      );
    }
    final grants = <RoleGrant>[];
    try {
      final rows = await deps.wyrm
          .invoke('$root/sys', 'get_permissions')
          .toList();
      for (final r in rows) {
        for (final g in switch (r) {
          VArray(:final v) => v,
          _ => [r],
        }) {
          grants.add(
            RoleGrant(
              subject: str(g['subject']) ?? '',
              path: str(g['path']) ?? '',
              level: str(g['level']) ?? '',
              source: str(g['source']) ?? '',
            ),
          );
        }
      }
    } on WyrmException {
      // No config on sys.
    }
    final audit = <String>[];
    try {
      final rows = await deps.wyrm
          .invoke('$root/sys/audit', 'tail', Value.from({'n': 200}))
          .toList();
      for (final r in rows) {
        for (final e in switch (r) {
          VArray(:final v) => v,
          _ => [r],
        }) {
          audit.add(_line(e));
        }
      }
    } on WyrmException {
      // No config on sys.
    }
    return state.copyWith.access(
      users: users.lock,
      grants: grants.lock,
      audit: audit.reversed.toList().lock,
    );
  }

  static String _line(Value e) {
    final m = toDart(e);
    if (m is! Map<String, Object?>) {
      return '$m';
    }
    final t = m['time'] ?? m['t'] ?? '';
    final who = m['who'] ?? m['by'] ?? m['subject'] ?? '';
    final what = [
      m['op'] ?? m['event'] ?? '',
      m['key'] ?? m['target'] ?? '',
      m['action'] ?? '',
    ].where((x) => '$x'.isNotEmpty).join(' ');
    final rest = m['result'] ?? m['status'] ?? '';
    return [t, who, what, rest].where((x) => '$x'.isNotEmpty).join('  ');
  }
}
