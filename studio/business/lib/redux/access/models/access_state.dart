import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:models/access_tab.dart';
import 'package:models/audit_line.dart';
import 'package:models/role_grant.dart';
import 'package:models/user_info.dart';

part 'access_state.freezed.dart';

@freezed
abstract class AccessState with _$AccessState {
  const factory AccessState({
    @Default(IListConst([])) IList<UserInfo> users,
    @Default(IListConst([])) IList<RoleGrant> grants,
    @Default(IListConst([])) IList<AuditLine> audit,
    String? selected,
    @Default(AccessTab.users) AccessTab tab,
    @Default(false) bool shown,
  }) = _AccessState;
}
