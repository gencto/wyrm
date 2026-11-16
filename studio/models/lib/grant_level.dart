import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:wyrm_core/wyrm_core.dart' show Perm;

part 'grant_level.freezed.dart';

/// The level of a grant of `sys` ▸ `get_permissions` (wyrm-admin
/// `perm_row`): an access level for a gateway role's or a link's grant, or
/// the messages and flows of a rule of the router's ACL, as the broker
/// words them (`put, query (ingress/egress)`); an ACL rule is no level.
@freezed
sealed class GrantLevel with _$GrantLevel {
  /// A gateway role's or a link's grant.
  const factory GrantLevel.perm(Perm perm) = GrantLevelPerm;

  /// A rule of the router's ACL, in the broker's words.
  const factory GrantLevel.rule(String text) = GrantLevelRule;
}
