import 'package:freezed_annotation/freezed_annotation.dart';

import 'grant_level.dart';
import 'grant_source.dart';

part 'role_grant.freezed.dart';

/// One grant of a role or a subject (`sys` ▸ `get_permissions`).
@freezed
abstract class RoleGrant with _$RoleGrant {
  const factory RoleGrant({
    /// The role or subject (`operator`, `link:modbus`).
    required String subject,

    /// A key pattern (`wy/{site}/downstream/**`).
    required String path,

    /// An access level; for a rule of the ACL, its messages and flows.
    required GrantLevel level,

    /// Where it comes from (a row from a source this client does not know
    /// is refused at decode: its level could not be read).
    required GrantSource source,
  }) = _RoleGrant;
}
