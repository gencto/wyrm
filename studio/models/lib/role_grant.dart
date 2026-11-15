import 'package:freezed_annotation/freezed_annotation.dart';

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

    /// `none`, `list`, `read`, `write`, `config`; for a rule of the ACL,
    /// its messages and flows, as the broker words them.
    required String level,

    /// Where it comes from; null for a source this client does not know.
    GrantSource? source,
  }) = _RoleGrant;
}
