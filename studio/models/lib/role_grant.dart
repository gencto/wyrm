import 'package:freezed_annotation/freezed_annotation.dart';

part 'role_grant.freezed.dart';

/// One grant of a role or a subject (`sys` ▸ `get_permissions`).
@freezed
abstract class RoleGrant with _$RoleGrant {
  const factory RoleGrant({
    /// The role or subject (`operator`, `link:modbus`).
    required String subject,

    /// A key pattern (`wy/{site}/downstream/**`).
    required String path,

    /// `none`, `list`, `read`, `write`, `config`.
    required String level,

    /// Where it comes from: `gateway`, `link`, `peer`, …
    @Default('') String source,
  }) = _RoleGrant;
}
